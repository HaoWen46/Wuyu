import 'package:wuyu_app/codex/events.dart';

/// Accumulates streamed text deltas per item ID.
///
/// The server sends `item/agentMessage/delta` events with a `delta` string
/// and an `itemId`. Multiple items can stream concurrently (e.g. commentary
/// then final answer), so each item maintains its own buffer.
class AgentMessageAccumulator {
  final _buffers = <String, StringBuffer>{};

  /// Apply a delta event, appending to the buffer for [event.itemId].
  void apply(AgentMessageDeltaEvent event) {
    _buffers.putIfAbsent(event.itemId, StringBuffer.new).write(event.delta);
  }

  /// Current accumulated text for [itemId], or empty string if unseen.
  String textFor(String itemId) => _buffers[itemId]?.toString() ?? '';

  /// All item IDs that have received at least one delta.
  Iterable<String> get itemIds => _buffers.keys;

  /// Reset all buffers (call between turns).
  void clear() => _buffers.clear();
}
