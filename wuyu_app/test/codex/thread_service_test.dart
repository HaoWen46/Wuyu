import 'package:flutter_test/flutter_test.dart';
import 'package:wuyu_dart/wuyu_dart.dart';
import 'package:wuyu_app/codex/events.dart';
import 'package:wuyu_app/codex/thread_service.dart';
import '../helpers/fake_transport.dart';

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

  group('ThreadService.listThreads', () {
    test('returns parsed ThreadSummary list sorted newest-first', () async {
      final transport = FakeTransport(incoming: [
        JsonRpcResponse(id: 1, result: {
          'data': [
            {'id': 'thr_1', 'created_at': 1742209200}, // 2026-03-17T10:00:00Z
            {'id': 'thr_2', 'created_at': 1742212800}, // 2026-03-17T11:00:00Z
          ],
        }),
      ]);
      final session = Session(transport)..start();
      final svc = ThreadService(session);

      final threads = await svc.listThreads();

      // Sorted newest-first: thr_2 (11:00) before thr_1 (10:00).
      expect(threads, hasLength(2));
      expect(threads[0].id, 'thr_2');
      expect(threads[0].createdAt,
          DateTime.fromMillisecondsSinceEpoch(1742212800 * 1000, isUtc: true));
      expect(threads[1].id, 'thr_1');
      final req = transport.sent.first as JsonRpcRequest;
      expect(req.method, 'thread/list');
    });

    test('returns empty list when no threads exist', () async {
      final transport = FakeTransport(incoming: [
        JsonRpcResponse(id: 1, result: {'data': []}),
      ]);
      final session = Session(transport)..start();
      final svc = ThreadService(session);

      final threads = await svc.listThreads();

      expect(threads, isEmpty);
    });
  });
}
