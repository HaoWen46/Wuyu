import 'package:flutter_test/flutter_test.dart';
import 'package:wuyu_app/codex/codex_detector.dart';
import 'package:wuyu_app/ssh/remote_runner.dart';

class FakeRemoteRunner implements RemoteRunner {
  final Map<String, (String, int)> _responses;

  FakeRemoteRunner(this._responses);

  @override
  Future<(String stdout, int exitCode)> run(String command) async =>
      _responses[command] ?? ('', 1);
}

class _TrackingRunner implements RemoteRunner {
  final Map<String, (String, int)> responses;
  final void Function(String command) onCall;

  _TrackingRunner({required this.responses, required this.onCall});

  @override
  Future<(String stdout, int exitCode)> run(String command) async {
    onCall(command);
    return responses[command] ?? ('', 1);
  }
}

void main() {
  group('CodexDetector', () {
    test('codex found with app-server — returns CodexFound with all fields',
        () async {
      final detector = CodexDetector(FakeRemoteRunner({
        'command -v codex 2>/dev/null': ('/home/user/.local/bin/codex\n', 0),
        'codex --version 2>&1': ('codex-cli 0.114.0\n', 0),
        'codex app-server --help 2>/dev/null': ('...help text...\n', 0),
      }));

      final found = await detector.detect() as CodexFound;
      expect(found.path, '/home/user/.local/bin/codex');
      expect(found.version, 'codex-cli 0.114.0');
      expect(found.hasAppServer, isTrue);
    });

    test('codex found but no app-server — hasAppServer is false', () async {
      final detector = CodexDetector(FakeRemoteRunner({
        'command -v codex 2>/dev/null': ('/usr/local/bin/codex\n', 0),
        'codex --version 2>&1': ('codex-cli 0.50.0\n', 0),
        'codex app-server --help 2>/dev/null': ('', 1),
      }));

      final found = await detector.detect() as CodexFound;
      expect(found.hasAppServer, isFalse);
    });

    test('codex not in PATH — returns CodexNotFound', () async {
      final detector = CodexDetector(FakeRemoteRunner({
        'command -v codex 2>/dev/null': ('', 1),
      }));

      expect(await detector.detect(), isA<CodexNotFound>());
    });

    test('command -v exits 0 but empty stdout — returns CodexNotFound',
        () async {
      // Some shells return exit 0 with empty output in edge cases.
      final detector = CodexDetector(FakeRemoteRunner({
        'command -v codex 2>/dev/null': ('   \n', 0),
      }));

      expect(await detector.detect(), isA<CodexNotFound>());
    });

    test('version command not called when codex absent', () async {
      final called = <String>[];
      final detector = CodexDetector(_TrackingRunner(
        responses: {'command -v codex 2>/dev/null': ('', 1)},
        onCall: called.add,
      ));

      await detector.detect();
      expect(called, isNot(contains('codex --version 2>&1')));
      expect(called, isNot(contains('codex app-server --help 2>/dev/null')));
    });

    test('version output is trimmed', () async {
      final detector = CodexDetector(FakeRemoteRunner({
        'command -v codex 2>/dev/null': ('/usr/local/bin/codex\n', 0),
        'codex --version 2>&1': ('\ncodex-cli 1.0.0\n\n', 0),
      }));

      final found = await detector.detect() as CodexFound;
      expect(found.version, 'codex-cli 1.0.0');
    });
  });
}
