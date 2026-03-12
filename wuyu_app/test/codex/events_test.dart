import 'package:flutter_test/flutter_test.dart';
import 'package:wuyu_dart/wuyu_dart.dart';
import 'package:wuyu_app/codex/events.dart';

void main() {
  group('NotificationParser', () {
    AppServerEvent parse(String method, Map<String, Object?> params) =>
        NotificationParser.parse(
            JsonRpcNotification(method: method, params: params));

    test('thread/started → ThreadStartedEvent', () {
      final e = parse('thread/started', {'threadId': 'thr_1'});
      expect(e, isA<ThreadStartedEvent>());
      expect((e as ThreadStartedEvent).threadId, 'thr_1');
    });

    test('turn/started → TurnStartedEvent with nested turn.id', () {
      final e = parse('turn/started', {
        'threadId': 'thr_1',
        'turn': {'id': 'turn_a', 'status': 'inProgress', 'items': []},
      });
      expect(e, isA<TurnStartedEvent>());
      final t = e as TurnStartedEvent;
      expect(t.threadId, 'thr_1');
      expect(t.turnId, 'turn_a');
    });

    test('turn/completed → TurnCompletedEvent with status', () {
      final e = parse('turn/completed', {
        'threadId': 'thr_1',
        'turn': {'id': 'turn_a', 'status': 'completed'},
      });
      expect(e, isA<TurnCompletedEvent>());
      final t = e as TurnCompletedEvent;
      expect(t.status, 'completed');
      expect(t.turnId, 'turn_a');
    });

    test('item/agentMessage/delta → AgentMessageDeltaEvent', () {
      final e = parse('item/agentMessage/delta', {
        'threadId': 'thr_1',
        'turnId': 'turn_a',
        'itemId': 'item_x',
        'delta': 'Hello',
      });
      expect(e, isA<AgentMessageDeltaEvent>());
      final d = e as AgentMessageDeltaEvent;
      expect(d.itemId, 'item_x');
      expect(d.delta, 'Hello');
    });

    test('unknown method → UnknownEvent', () {
      final e = parse('thread/archived', {'threadId': 'thr_1'});
      expect(e, isA<UnknownEvent>());
      expect((e as UnknownEvent).method, 'thread/archived');
    });
  });
}
