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
    // runAsync lets Future.microtask-based FakeTransport resolve in real time.
    await tester.runAsync(() async {
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
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.textContaining('thr_abc'), findsOneWidget);
      expect(find.textContaining('thr_xyz'), findsOneWidget);
    });
  });

  testWidgets('shows empty state when no threads', (tester) async {
    await tester.runAsync(() async {
      final svc = _makeService([
        JsonRpcResponse(id: 1, result: {'data': []}),
      ]);

      await tester.pumpWidget(_wrap(
        ThreadListScreen(service: svc, cwd: '/project'),
      ));
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('No threads yet.'), findsOneWidget);
    });
  });

  testWidgets('shows error banner on fetch failure', (tester) async {
    // Empty transport → Session cancels pending request with StateError.
    await tester.runAsync(() async {
      final svc = _makeService([]);

      await tester.pumpWidget(_wrap(
        ThreadListScreen(service: svc, cwd: '/project'),
      ));
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.byType(MaterialBanner), findsOneWidget);
    });
  });
}
