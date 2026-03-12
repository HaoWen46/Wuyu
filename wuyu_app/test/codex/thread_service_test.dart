import 'package:flutter_test/flutter_test.dart';
import 'package:wuyu_dart/wuyu_dart.dart';
import 'package:wuyu_app/codex/events.dart';
import 'package:wuyu_app/codex/thread_service.dart';

// Minimal in-memory transport (same pattern as app_server_service_test.dart).
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
  group('ThreadService.startThread', () {
    test('sends thread/start with cwd and returns thread id', () async {
      final transport = FakeTransport(incoming: [
        JsonRpcResponse(id: 1, result: {
          'thread': {'id': 'thr_abc'}
        }),
      ]);
      final session = Session(transport)..start();
      final svc = ThreadService(session);

      final id = await svc.startThread(cwd: '/my/project');

      expect(id, 'thr_abc');
      final req = transport.sent.first as JsonRpcRequest;
      expect(req.method, 'thread/start');
      expect(req.params?['cwd'], '/my/project');
    });
  });

  group('ThreadService.startTurn', () {
    test('sends turn/start with threadId and text input', () async {
      final transport = FakeTransport(incoming: [
        JsonRpcResponse(id: 1, result: {}),
      ]);
      final session = Session(transport)..start();
      final svc = ThreadService(session);

      await svc.startTurn(
          threadId: 'thr_1', text: 'Run the tests', cwd: '/my/project');

      final req = transport.sent.first as JsonRpcRequest;
      expect(req.method, 'turn/start');
      expect(req.params?['threadId'], 'thr_1');
      expect(req.params?['cwd'], '/my/project');
      final input = req.params?['input'] as List;
      expect(input.first, {'type': 'text', 'text': 'Run the tests'});
    });
  });

  group('ThreadService.events', () {
    test('yields parsed events from server notifications', () async {
      final transport = FakeTransport(incoming: [
        JsonRpcNotification(
            method: 'thread/started', params: {'threadId': 'thr_1'}),
        JsonRpcNotification(method: 'item/agentMessage/delta', params: {
          'threadId': 'thr_1',
          'turnId': 'turn_a',
          'itemId': 'item_x',
          'delta': 'Hi',
        }),
      ]);
      final session = Session(transport)..start();
      final svc = ThreadService(session);

      final events = await svc.events.take(2).toList();

      expect(events[0], isA<ThreadStartedEvent>());
      expect(events[1], isA<AgentMessageDeltaEvent>());
    });

    test('stream ends cleanly when transport closes', () async {
      final transport = FakeTransport(incoming: [
        JsonRpcNotification(
            method: 'thread/started', params: {'threadId': 'thr_1'}),
      ]);
      final session = Session(transport)..start();
      final svc = ThreadService(session);

      final events = await svc.events.toList();

      expect(events, hasLength(1));
      expect(events.first, isA<ThreadStartedEvent>());
    });
  });
}
