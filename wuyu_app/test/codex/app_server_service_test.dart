import 'package:flutter_test/flutter_test.dart';
import 'package:wuyu_dart/wuyu_dart.dart';
import 'package:wuyu_app/codex/app_server_service.dart';

/// Minimal in-memory [Transport] for testing. Pre-loaded with incoming
/// messages; collects outbound messages in [sent].
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
      return null;
    }
    await Future.microtask(() {});
    return _incoming[_idx++];
  }

  @override
  Future<void> close() async => _connected = false;

  @override
  bool get isConnected => _connected;
}

void main() {
  group('AppServerService.handshake', () {
    test('sends initialize with wuyu clientInfo then initialized notification',
        () async {
      final transport = FakeTransport(incoming: [
        JsonRpcResponse(id: 1, result: {'userAgent': 'codex/1.0'}),
      ]);

      await AppServerService.handshake(transport);

      expect(transport.sent, hasLength(2));

      final req = transport.sent[0] as JsonRpcRequest;
      expect(req.method, 'initialize');
      expect(req.params?['clientInfo'], {'name': 'wuyu', 'version': '0.1.0'});

      final notif = transport.sent[1] as JsonRpcNotification;
      expect(notif.method, 'initialized');
    });

    test('returns a ready Session that can receive notifications', () async {
      final notif = JsonRpcNotification(
          method: 'thread/started', params: {'threadId': 'abc'});
      final transport = FakeTransport(incoming: [
        JsonRpcResponse(id: 1, result: {}),
        notif,
      ]);

      final session = await AppServerService.handshake(transport);
      final received = await session.receiveNotification();

      expect(received.method, 'thread/started');
    });

    test('throws SessionError if server returns error on initialize', () async {
      final transport = FakeTransport(incoming: [
        JsonRpcErrorResponse(
          id: 1,
          error: JsonRpcError(code: -32600, message: 'Invalid request'),
        ),
      ]);

      await expectLater(
        AppServerService.handshake(transport),
        throwsA(isA<SessionError>().having((e) => e.code, 'code', -32600)),
      );
    });
  });
}
