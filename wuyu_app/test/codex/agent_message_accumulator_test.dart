import 'package:flutter_test/flutter_test.dart';
import 'package:wuyu_app/codex/agent_message_accumulator.dart';
import 'package:wuyu_app/codex/events.dart';

AgentMessageDeltaEvent delta(String itemId, String text) =>
    AgentMessageDeltaEvent(
      threadId: 'thr_1',
      turnId: 'turn_a',
      itemId: itemId,
      delta: text,
    );

void main() {
  late AgentMessageAccumulator acc;

  setUp(() => acc = AgentMessageAccumulator());

  group('AgentMessageAccumulator', () {
    test('empty accumulator returns empty string for any itemId', () {
      expect(acc.textFor('item_x'), '');
    });

    test('accumulates deltas for a single item', () {
      acc.apply(delta('item_x', 'Hello'));
      acc.apply(delta('item_x', ', '));
      acc.apply(delta('item_x', 'world!'));

      expect(acc.textFor('item_x'), 'Hello, world!');
    });

    test('tracks multiple items independently', () {
      acc.apply(delta('item_a', 'First '));
      acc.apply(delta('item_b', 'Second '));
      acc.apply(delta('item_a', 'item'));
      acc.apply(delta('item_b', 'item'));

      expect(acc.textFor('item_a'), 'First item');
      expect(acc.textFor('item_b'), 'Second item');
    });

    test('itemIds returns all seen item ids', () {
      acc.apply(delta('item_a', 'x'));
      acc.apply(delta('item_b', 'y'));

      expect(acc.itemIds, containsAll(['item_a', 'item_b']));
    });

    test('clear resets all buffers', () {
      acc.apply(delta('item_x', 'Hello'));
      acc.clear();

      expect(acc.textFor('item_x'), '');
      expect(acc.itemIds, isEmpty);
    });
  });
}
