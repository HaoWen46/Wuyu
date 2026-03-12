import 'package:wuyu_dart/wuyu_dart.dart';

// ---------------------------------------------------------------------------
// Event hierarchy
// ---------------------------------------------------------------------------

/// Typed representation of a server notification relevant to M2 chat.
sealed class AppServerEvent {
  const AppServerEvent();
}

/// `thread/started` — server created (or resumed) a thread.
final class ThreadStartedEvent extends AppServerEvent {
  final String threadId;
  const ThreadStartedEvent(this.threadId);
}

/// `turn/started` — agent began processing a turn.
final class TurnStartedEvent extends AppServerEvent {
  final String threadId;
  final String turnId;
  const TurnStartedEvent({required this.threadId, required this.turnId});
}

/// `turn/completed` — agent finished a turn.
final class TurnCompletedEvent extends AppServerEvent {
  final String threadId;
  final String turnId;

  /// `'completed'`, `'interrupted'`, or `'failed'`.
  final String status;

  const TurnCompletedEvent({
    required this.threadId,
    required this.turnId,
    required this.status,
  });
}

/// `item/agentMessage/delta` — one streamed text chunk from the agent.
final class AgentMessageDeltaEvent extends AppServerEvent {
  final String threadId;
  final String turnId;
  final String itemId;
  final String delta;

  const AgentMessageDeltaEvent({
    required this.threadId,
    required this.turnId,
    required this.itemId,
    required this.delta,
  });
}

/// Any notification method not handled above (ignored by the chat UI).
final class UnknownEvent extends AppServerEvent {
  final String method;
  const UnknownEvent(this.method);
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

/// Parses a raw [JsonRpcNotification] into a typed [AppServerEvent].
class NotificationParser {
  const NotificationParser._();

  static AppServerEvent parse(JsonRpcNotification notif) {
    final p = notif.params ?? {};
    return switch (notif.method) {
      'thread/started' => ThreadStartedEvent(
          p['threadId'] as String,
        ),
      'turn/started' => TurnStartedEvent(
          threadId: p['threadId'] as String,
          turnId: ((p['turn'] as Map)['id']) as String,
        ),
      'turn/completed' => TurnCompletedEvent(
          threadId: p['threadId'] as String,
          turnId: ((p['turn'] as Map)['id']) as String,
          status: ((p['turn'] as Map)['status']) as String,
        ),
      'item/agentMessage/delta' => AgentMessageDeltaEvent(
          threadId: p['threadId'] as String,
          turnId: p['turnId'] as String,
          itemId: p['itemId'] as String,
          delta: p['delta'] as String,
        ),
      _ => UnknownEvent(notif.method),
    };
  }
}
