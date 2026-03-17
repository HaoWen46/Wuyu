# M2 Thread List Screen — Design Spec

**Date:** 2026-03-17
**Milestone:** M2 completion
**Status:** Approved

## Goal

Complete M2 by adding a thread list screen between `DevConnectScreen` and `ChatScreen`. After connecting, the user lands on the thread list, can tap an existing thread to resume it, or start a new one.

## Decisions

- Thread list shows: thread ID + timestamp only (minimal, always accurate)
- Navigation: `DevConnectScreen` → `ThreadListScreen` → `ChatScreen`
- Session: one shared `Session` / `ThreadService` passed through navigation — no new SSH connections
- Data strategy: fetch on enter (`initState`), pull-to-refresh, no polling, no caching

## Architecture

### 1. `ThreadSummary` data class (in `thread_service.dart`)

```dart
final class ThreadSummary {
  final String id;
  final DateTime updatedAt;
}
```

### 2. `ThreadService.listThreads()` (new method)

```dart
Future<List<ThreadSummary>> listThreads() async {
  final result = await _session.request('thread/list', params: {});
  // parse list of {id, updatedAt} from result
  return ...;
}
```

### 3. `ThreadListScreen` (new file: `wuyu_app/lib/codex/thread_list_screen.dart`)

- `StatefulWidget` — takes `ThreadService service` + `String cwd`
- `initState`: calls `service.listThreads()`, stores result
- Shows `CircularProgressIndicator` while loading, error banner on failure
- `RefreshIndicator` wrapping a `ListView.builder` of thread rows
- Each row: thread ID (truncated) + formatted timestamp, `onTap` pushes `ChatScreen` with `threadId`
- FAB or AppBar action: "New thread" — pushes `ChatScreen` with no `threadId`

### 4. `ChatScreen` changes

Current: always calls `startThread()` in `initState`.

New constructor signature:
```dart
const ChatScreen({
  super.key,
  required this.service,
  required this.cwd,
  this.threadId,   // null = start new, non-null = resume
});
```

`initState` branches:
- `threadId == null` → `startThread()` as before
- `threadId != null` → `resumeThread(threadId)` (already exists in `ThreadService`)

AppBar title: show thread ID when resuming (not just "Thread").

### 5. `DevConnectScreen` change

After handshake, push `ThreadListScreen` instead of `ChatScreen`.

## Performance contract

- `thread/list` called once on screen enter; never polled
- Pull-to-refresh is the only re-fetch mechanism
- `ThreadListScreen` holds no stream subscriptions — nothing to leak in `dispose`
- `ListView.builder` for virtualized rendering (consistent with `ChatScreen`)

## Files changed

| File | Change |
|------|--------|
| `wuyu_app/lib/codex/thread_service.dart` | Add `ThreadSummary` class + `listThreads()` |
| `wuyu_app/lib/codex/thread_list_screen.dart` | New file |
| `wuyu_app/lib/codex/chat_screen.dart` | Add optional `threadId` param; branch in `initState` |
| `wuyu_app/lib/dev_connect_screen.dart` | Push `ThreadListScreen` instead of `ChatScreen` |

## Out of scope

- Thread list caching / Riverpod state (M4)
- Optimistic thread insert after creation
- Thread delete / archive UI
- Thread metadata beyond ID + timestamp
- Slash command hints (not a protocol feature — see `.notes/slash-commands.md`)
