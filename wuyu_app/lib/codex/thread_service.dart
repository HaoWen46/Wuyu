import 'package:wuyu_dart/wuyu_dart.dart';
import 'package:wuyu_app/codex/events.dart';

/// Lightweight summary of a thread returned by `thread/list`.
final class ThreadSummary {
  final String id;

  /// Thread creation time (UTC). Source: `created_at` Unix epoch seconds.
  final DateTime createdAt;

  const ThreadSummary({required this.id, required this.createdAt});
}

/// Wraps [Session] with typed methods for the thread/turn lifecycle.
class ThreadService {
  final Session _session;

  ThreadService(this._session);

  /// Sends `thread/start` and returns the new thread ID.
  Future<String> startThread({required String cwd}) async {
    final result = await _session.request(
      'thread/start',
      params: {'cwd': cwd},
    );
    final map = result as Map<String, Object?>;
    return (map['thread'] as Map<String, Object?>)['id'] as String;
  }

  /// Sends `turn/start` for a text message.
  ///
  /// The turn ID arrives asynchronously via a `turn/started` notification;
  /// listen to [events] to track it.
  Future<void> startTurn({
    required String threadId,
    required String text,
    required String cwd,
  }) async {
    await _session.request(
      'turn/start',
      params: {
        'threadId': threadId,
        'input': [
          {'type': 'text', 'text': text}
        ],
        'cwd': cwd,
      },
    );
  }

  /// Sends `thread/resume` to re-subscribe to events on an existing thread.
  ///
  /// Use [Session.request] with `thread/read` after this to get full state.
  Future<void> resumeThread(String threadId) async {
    await _session.request(
      'thread/resume',
      params: {'threadId': threadId},
    );
  }

  /// A continuous stream of typed [AppServerEvent]s from the server.
  ///
  /// Ends when the [Session] transport closes (receiveNotification throws
  /// [StateError] once the pump drains all waiters on EOF).
  Stream<AppServerEvent> get events async* {
    try {
      while (true) {
        final notif = await _session.receiveNotification();
        yield NotificationParser.parse(notif);
      }
    } on StateError {
      // Transport closed — stream ends naturally.
    }
  }

  /// Sends `thread/list` and returns summaries sorted newest-first.
  Future<List<ThreadSummary>> listThreads() async {
    final result = await _session.request('thread/list', params: {});
    final map = result as Map<String, Object?>;
    final raw = map['data'] as List<Object?>;
    final summaries = raw.map((e) {
      final t = e as Map<String, Object?>;
      final epochSec = t['created_at'] as int;
      return ThreadSummary(
        id: t['id'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          epochSec * 1000,
          isUtc: true,
        ),
      );
    }).toList();
    summaries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return summaries;
  }
}
