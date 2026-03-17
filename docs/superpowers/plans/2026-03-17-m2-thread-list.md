# M2 Thread List Screen Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete M2 by adding a `ThreadListScreen` between `DevConnectScreen` and `ChatScreen` — shows existing threads, lets user tap to resume or start a new one.

**Architecture:** One shared `Session`/`ThreadService` is passed through navigation. `ThreadListScreen` fetches `thread/list` on enter (no polling). `ChatScreen` gets an optional `threadId` param — null means start new, non-null means resume.

**Tech Stack:** Flutter, `wuyu_dart` Session/Transport, `flutter_test` widget tests, shared `FakeTransport` helper

**Run tests:** `export PATH="/tmp2/b11902156/flutter/bin:$PATH" && cd wuyu_app && flutter test`
**Run analysis:** `flutter analyze`

### Protocol note: `thread/list` wire shape

The Codex app-server returns:
```json
{ "data": [ { "id": "thr_abc", "created_at": 1742209200 } ], "nextCursor": null }
```
- Key is `data`, **not** `threads`
- `created_at` is a Unix epoch integer (seconds), **not** an ISO string

### Known limitation: resumed threads show blank history

`thread/resume` re-subscribes to **new** events only — it does not replay past messages.
After resuming, `ChatScreen` will appear empty even for an existing conversation.
Full history hydration via `thread/read` is deferred to M5 (reconnection & offline resilience).
The AppBar title says "Resume · <id>" to make this expectation explicit to the user.

---

## Chunk 0: Extract shared FakeTransport helper

### Task 0: Move `FakeTransport` to a shared test helper

**Files:**
- Create: `wuyu_app/test/helpers/fake_transport.dart`
- Modify: `wuyu_app/test/codex/thread_service_test.dart`

`FakeTransport` is currently defined inline in `thread_service_test.dart`. The thread list test
will need the same class. Extract it once so both files import from one place.

- [ ] **Step 1: Create the shared helper**

Create `wuyu_app/test/helpers/fake_transport.dart`:

```dart
import 'package:wuyu_dart/wuyu_dart.dart';

/// In-memory [Transport] for unit tests.
///
/// Plays back a fixed list of incoming messages. Returns null (transport
/// closed) once the list is exhausted.
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
```

- [ ] **Step 2: Update `thread_service_test.dart` to import the helper**

In `wuyu_app/test/codex/thread_service_test.dart`:

1. Remove the inline `FakeTransport` class definition (lines 7–33).
2. Add import at the top:
```dart
import '../helpers/fake_transport.dart';
```

- [ ] **Step 3: Run tests to confirm nothing broke**

```bash
export PATH="/tmp2/b11902156/flutter/bin:$PATH"
cd wuyu_app && flutter test test/codex/thread_service_test.dart
```

Expected: All 4 existing tests pass.

- [ ] **Step 4: Commit**

```bash
git add wuyu_app/test/helpers/fake_transport.dart \
        wuyu_app/test/codex/thread_service_test.dart
git commit -m "test: extract FakeTransport to shared helper"
```

---

## Chunk 1: ThreadSummary + listThreads()

### Task 1: Add `ThreadSummary` and `listThreads()` to `ThreadService`

**Files:**
- Modify: `wuyu_app/lib/codex/thread_service.dart`
- Modify: `wuyu_app/test/codex/thread_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `wuyu_app/test/codex/thread_service_test.dart` inside `main()`:

```dart
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
```

- [ ] **Step 2: Run to verify tests fail**

```bash
flutter test test/codex/thread_service_test.dart
```

Expected: FAIL — `ThreadSummary` and `listThreads` not defined.

- [ ] **Step 3: Add `ThreadSummary` and `listThreads()` to `thread_service.dart`**

Add `ThreadSummary` before the `ThreadService` class:

```dart
/// Lightweight summary of a thread returned by `thread/list`.
final class ThreadSummary {
  final String id;

  /// Thread creation time (UTC). Source: `created_at` Unix epoch seconds.
  final DateTime createdAt;

  const ThreadSummary({required this.id, required this.createdAt});
}
```

Add `listThreads()` inside `ThreadService`:

```dart
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/codex/thread_service_test.dart
```

Expected: All 6 tests pass (4 existing + 2 new).

- [ ] **Step 5: Run full test suite and analyze**

```bash
flutter test && flutter analyze
```

Expected: All tests pass, no analysis issues.

- [ ] **Step 6: Commit**

```bash
git add wuyu_app/lib/codex/thread_service.dart \
        wuyu_app/test/codex/thread_service_test.dart
git commit -m "feat(M2): ThreadSummary + ThreadService.listThreads()"
```

---

## Chunk 2: ChatScreen resume support

### Task 2: Add optional `threadId` to `ChatScreen`

**Files:**
- Modify: `wuyu_app/lib/codex/chat_screen.dart`

Currently `ChatScreen` always calls `startThread()`. When `threadId` is provided, it should
call `resumeThread()` instead. Resumed threads show no prior history (see known limitation above).

- [ ] **Step 1: Add `threadId` param to `ChatScreen`**

In `chat_screen.dart`, update the `ChatScreen` widget declaration:

```dart
class ChatScreen extends StatefulWidget {
  final ThreadService service;
  final String cwd;

  /// If non-null, resume this existing thread instead of starting a new one.
  ///
  /// Note: only new events are delivered after resume — prior message history
  /// is not replayed. History hydration via `thread/read` is M5 work.
  final String? threadId;

  const ChatScreen({
    super.key,
    required this.service,
    required this.cwd,
    this.threadId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}
```

- [ ] **Step 2: Replace `_startThread()` with `_initThread()` in the state class**

Replace the `_startThread()` method with:

```dart
Future<void> _initThread() async {
  try {
    if (widget.threadId != null) {
      await widget.service.resumeThread(widget.threadId!);
      if (mounted) setState(() => _threadId = widget.threadId);
    } else {
      final id = await widget.service.startThread(cwd: widget.cwd);
      if (mounted) setState(() => _threadId = id);
    }
  } catch (e) {
    if (mounted) setState(() => _error = e.toString());
  }
}
```

Update `initState` to call `_initThread()` instead of `_startThread()`.

- [ ] **Step 3: Update AppBar title**

```dart
title: Text(_threadId == null
    ? 'Connecting…'
    : widget.threadId != null
        ? 'Resume · $_threadId'
        : 'Thread · $_threadId'),
```

- [ ] **Step 4: Run tests and analyze**

```bash
flutter test && flutter analyze
```

Expected: All tests pass. Callers in `dev_connect_screen.dart` pass no `threadId`, so default `null` keeps old behavior.

- [ ] **Step 5: Commit**

```bash
git add wuyu_app/lib/codex/chat_screen.dart
git commit -m "feat(M2): ChatScreen accepts optional threadId for resume"
```

---

## Chunk 3: ThreadListScreen

### Task 3: Create `ThreadListScreen`

**Files:**
- Create: `wuyu_app/lib/codex/thread_list_screen.dart`
- Create: `wuyu_app/test/codex/thread_list_screen_test.dart`

- [ ] **Step 1: Write the widget tests**

Create `wuyu_app/test/codex/thread_list_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuyu_dart/wuyu_dart.dart';
import 'package:wuyu_app/codex/thread_list_screen.dart';
import 'package:wuyu_app/codex/thread_service.dart';
import '../helpers/fake_transport.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

ThreadService _makeService(List<Object?> incoming) {
  final session = Session(FakeTransport(incoming: incoming))..start();
  return ThreadService(session);
}

void main() {
  testWidgets('shows loading indicator while fetching', (tester) async {
    // FakeTransport with no items: receive() blocks until closed → loading spins.
    final session = Session(FakeTransport())..start();
    final svc = ThreadService(session);

    await tester.pumpWidget(_wrap(
      ThreadListScreen(service: svc, cwd: '/project'),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows thread list after fetch', (tester) async {
    final svc = _makeService([
      JsonRpcResponse(id: 1, result: {
        'data': [
          {'id': 'thr_abc', 'created_at': 1742209200},
          {'id': 'thr_xyz', 'created_at': 1742122800},
        ],
      }),
    ]);

    await tester.pumpWidget(_wrap(
      ThreadListScreen(service: svc, cwd: '/project'),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('thr_abc'), findsOneWidget);
    expect(find.textContaining('thr_xyz'), findsOneWidget);
  });

  testWidgets('shows empty state when no threads', (tester) async {
    final svc = _makeService([
      JsonRpcResponse(id: 1, result: {'data': []}),
    ]);

    await tester.pumpWidget(_wrap(
      ThreadListScreen(service: svc, cwd: '/project'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No threads yet.'), findsOneWidget);
  });

  testWidgets('shows error banner on fetch failure', (tester) async {
    // Empty transport → Session cancels pending request with StateError.
    final svc = _makeService([]);

    await tester.pumpWidget(_wrap(
      ThreadListScreen(service: svc, cwd: '/project'),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialBanner), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify tests fail**

```bash
flutter test test/codex/thread_list_screen_test.dart
```

Expected: FAIL — `ThreadListScreen` not defined.

- [ ] **Step 3: Implement `ThreadListScreen`**

Create `wuyu_app/lib/codex/thread_list_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:wuyu_app/codex/chat_screen.dart';
import 'package:wuyu_app/codex/thread_service.dart';

/// Lists existing threads for a project and lets the user resume one
/// or start a new one.
///
/// Fetches `thread/list` once on enter. Pull-to-refresh re-fetches.
/// No polling — the list is only as live as the last fetch.
class ThreadListScreen extends StatefulWidget {
  final ThreadService service;
  final String cwd;

  const ThreadListScreen({
    super.key,
    required this.service,
    required this.cwd,
  });

  @override
  State<ThreadListScreen> createState() => _ThreadListScreenState();
}

class _ThreadListScreenState extends State<ThreadListScreen> {
  List<ThreadSummary>? _threads;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _threads = null;
      _error = null;
    });
    try {
      final threads = await widget.service.listThreads();
      if (mounted) setState(() => _threads = threads);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _openThread(String? threadId) {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ChatScreen(
        service: widget.service,
        cwd: widget.cwd,
        threadId: threadId,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Threads'),
        backgroundColor: cs.inversePrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openThread(null),
        icon: const Icon(Icons.add),
        label: const Text('New thread'),
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: _fetch,
                  child: const Text('Retry'),
                ),
              ],
            ),
          Expanded(child: _buildBody(cs)),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_threads == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final threads = _threads ?? [];
    if (threads.isEmpty) {
      return Center(
        child: Text(
          'No threads yet.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.builder(
        itemCount: threads.length,
        itemBuilder: (context, i) => _buildRow(threads[i], cs),
      ),
    );
  }

  Widget _buildRow(ThreadSummary thread, ColorScheme cs) {
    final dt = thread.createdAt.toLocal();
    final label =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return ListTile(
      title: Text(
        thread.id,
        style: const TextStyle(fontFamily: 'monospace'),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openThread(thread.id),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/codex/thread_list_screen_test.dart
```

Expected: All 4 tests pass.

- [ ] **Step 5: Run full suite**

```bash
flutter test && flutter analyze
```

Expected: All tests pass, no issues.

- [ ] **Step 6: Commit**

```bash
git add wuyu_app/lib/codex/thread_list_screen.dart \
        wuyu_app/test/codex/thread_list_screen_test.dart
git commit -m "feat(M2): ThreadListScreen — fetch, empty state, error banner"
```

---

## Chunk 4: Wire navigation in DevConnectScreen

### Task 4: Push `ThreadListScreen` from `DevConnectScreen`

**Files:**
- Modify: `wuyu_app/lib/dev_connect_screen.dart`

The current code at line 67 uses `Navigator.of(context).push<void>(...)`. We replace the
destination from `ChatScreen` to `ThreadListScreen`. Keep `push<void>` (not `pushReplacement`)
so the user can navigate back to fix SSH details.

- [ ] **Step 1: Update imports and push target**

In `dev_connect_screen.dart`:

1. Replace the `chat_screen.dart` import with `thread_list_screen.dart`:
```dart
// Remove:
import 'package:wuyu_app/codex/chat_screen.dart';
// Add:
import 'package:wuyu_app/codex/thread_list_screen.dart';
```

2. Find the `Navigator.of(context).push<void>(...)` call (around line 67). Replace:

```dart
// Before:
await Navigator.of(context).push<void>(MaterialPageRoute(
  builder: (_) => ChatScreen(
    service: ThreadService(session),
    cwd: cwd,
  ),
));

// After:
await Navigator.of(context).push<void>(MaterialPageRoute(
  builder: (_) => ThreadListScreen(
    service: ThreadService(session),
    cwd: cwd,
  ),
));
```

Read the file before editing to match the exact existing code.

- [ ] **Step 2: Run full suite**

```bash
flutter test && flutter analyze
```

Expected: All tests pass, no issues.

- [ ] **Step 3: Commit**

```bash
git add wuyu_app/lib/dev_connect_screen.dart
git commit -m "feat(M2): wire DevConnectScreen → ThreadListScreen"
```

---

## Chunk 5: Final verification

- [ ] **Step 1: Run complete test suite**

```bash
export PATH="/tmp2/b11902156/flutter/bin:$PATH"
cd wuyu_app && flutter test --reporter expanded && flutter analyze
```

Expected: All tests pass (target: ~50+ tests), zero analysis warnings.

- [ ] **Step 2: Update PLAN.md M2 checkbox**

In `PLAN.md`, mark done:
```
- [x] Thread list: `thread/list`, show existing threads, tap to resume (`thread/resume`)
```

- [ ] **Step 3: Final commit**

```bash
git add PLAN.md
git commit -m "docs: mark M2 thread list complete in PLAN.md"
```
