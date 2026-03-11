import 'dart:async';

import 'package:test/test.dart';

import 'package:wuyu_dart/src/session.dart';

/// In-memory transport for tests. Pre-loaded with incoming messages.
final class FakeTransport implements Transport {
  final List<Object?> _incoming;
  final List<Object> sent = [];
  int _idx = 0;
  bool _connected = true;

  FakeTransport({List<Object?>? incoming}) : _incoming = incoming ?? [];

  @override
  void send(Object message) => sent.add(message);

  @override
  Future<Object?> receive() async {
    if (_idx >= _incoming.length) {
      _connected = false;
      return null; // EOF
    }
    // Yield to event loop so pump and test interleave naturally.
    await Future.microtask(() {});
    return _incoming[_idx++];
  }

  @override
  Future<void> close() async => _connected = false;

  @override
  bool get isConnected => _connected;
}

void main() {
  group('request/response correlation', () {
    test('request sends message and returns result', () async {
      final response = JsonRpcResponse(id: 1, result: {'userAgent': 'codex'});
      final t = FakeTransport(incoming: [response]);
      final session = Session(t)..start();

      final result = await session.request('initialize');

      expect(result, {'userAgent': 'codex'});
      expect(t.sent, hasLength(1));
      expect((t.sent.first as JsonRpcRequest).method, 'initialize');
    });

    test('concurrent requests are correlated correctly', () async {
      final resp1 = JsonRpcResponse(id: 1, result: 'first');
      final resp2 = JsonRpcResponse(id: 2, result: 'second');
      final t = FakeTransport(incoming: [resp1, resp2]);
      final session = Session(t)..start();

      final f1 = session.request('method/one');
      final f2 = session.request('method/two');

      expect(await f1, 'first');
      expect(await f2, 'second');
    });

    test('error response throws SessionError', () async {
      final errResp = JsonRpcErrorResponse(
        id: 1,
        error: JsonRpcError(code: -32601, message: 'Method not found'),
      );
      final t = FakeTransport(incoming: [errResp]);
      final session = Session(t)..start();

      expect(
        () => session.request('bad/method'),
        throwsA(isA<SessionError>().having((e) => e.code, 'code', -32601)),
      );
    });

    test('request ids are unique across calls', () async {
      final resp1 = JsonRpcResponse(id: 1, result: null);
      final resp2 = JsonRpcResponse(id: 2, result: null);
      final t = FakeTransport(incoming: [resp1, resp2]);
      final session = Session(t)..start();

      await session.request('a');
      await session.request('b');

      final ids = t.sent.cast<JsonRpcRequest>().map((r) => r.id).toList();
      expect(ids.toSet(), hasLength(2));
    });
  });

  group('notifications and server requests', () {
    test('server notifications are queued for consumption', () async {
      final notif = JsonRpcNotification(method: 'thread/started', params: {'threadId': 't1'});
      final t = FakeTransport(incoming: [notif]);
      final session = Session(t)..start();

      final received = await session.receiveNotification();

      expect(received.method, 'thread/started');
      expect(received.params, {'threadId': 't1'});
    });

    test('server-initiated requests are queued separately', () async {
      final serverReq = JsonRpcRequest(
        id: 'srv-1',
        method: 'item/commandExecution/requestApproval',
        params: {'command': ['ls']},
      );
      final t = FakeTransport(incoming: [serverReq]);
      final session = Session(t)..start();

      final received = await session.receiveServerRequest();

      expect(received.method, 'item/commandExecution/requestApproval');
      expect(received.id, 'srv-1');
    });

    test('notification and server request handled in same stream', () async {
      final notif = JsonRpcNotification(method: 'initialized');
      final serverReq = JsonRpcRequest(
        id: 99,
        method: 'item/fileChange/requestApproval',
      );
      final t = FakeTransport(incoming: [notif, serverReq]);
      final session = Session(t)..start();

      final n = await session.receiveNotification();
      final sr = await session.receiveServerRequest();

      expect(n.method, 'initialized');
      expect(sr.method, 'item/fileChange/requestApproval');
    });
  });

  group('initialize handshake', () {
    test('initialize sends request then initialized notification', () async {
      final initResponse = JsonRpcResponse(id: 1, result: {'userAgent': 'codex/1.0'});
      final t = FakeTransport(incoming: [initResponse]);
      final session = Session(t)..start();

      final result = await session.initialize(
        clientInfo: {'name': 'wuyu', 'version': '0.1.0'},
      );

      expect(result, {'userAgent': 'codex/1.0'});

      // First message: initialize request
      expect(t.sent, hasLength(2));
      final req = t.sent[0] as JsonRpcRequest;
      expect(req.method, 'initialize');
      expect(req.params?['clientInfo'], {'name': 'wuyu', 'version': '0.1.0'});

      // Second message: initialized notification
      final notif = t.sent[1] as JsonRpcNotification;
      expect(notif.method, 'initialized');
    });

    test('respond sends a response to a server-initiated request', () async {
      final serverReq = JsonRpcRequest(
        id: 'approval-1',
        method: 'item/commandExecution/requestApproval',
      );
      final t = FakeTransport(incoming: [serverReq]);
      final session = Session(t)..start();

      await session.receiveServerRequest();
      session.respond(requestId: 'approval-1', result: {'decision': 'accept'});

      final sent = t.sent.first as JsonRpcResponse;
      expect(sent.id, 'approval-1');
      expect(sent.result, {'decision': 'accept'});
    });
  });
}
