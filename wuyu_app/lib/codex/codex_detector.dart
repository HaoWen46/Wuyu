import 'package:wuyu_app/ssh/remote_runner.dart';

/// Result of probing the remote host for a Codex installation.
sealed class CodexStatus {
  const CodexStatus();
}

/// Codex is present and runnable on the remote host.
final class CodexFound extends CodexStatus {
  /// Absolute path to the codex binary (e.g. `/home/user/.local/bin/codex`).
  final String path;

  /// Output of `codex --version` (e.g. `codex-cli 0.114.0`).
  final String version;

  /// Whether `codex app-server` is available (experimental subcommand,
  /// absent in older versions).
  final bool hasAppServer;

  CodexFound({
    required this.path,
    required this.version,
    required this.hasAppServer,
  });
}

/// Codex was not found on the remote host's PATH.
final class CodexNotFound extends CodexStatus {
  const CodexNotFound();
}

/// Probes a remote host for a usable Codex installation.
class CodexDetector {
  final RemoteRunner _runner;

  CodexDetector(this._runner);

  /// Runs `command -v codex`, `codex --version`, and
  /// `codex app-server --help` over SSH.
  ///
  /// Returns [CodexFound] with path, version, and [CodexFound.hasAppServer],
  /// or [CodexNotFound] if codex is absent.
  Future<CodexStatus> detect() async {
    final (path, exitCode) = await _runner.run('command -v codex 2>/dev/null');
    if (exitCode != 0 || path.trim().isEmpty) {
      return const CodexNotFound();
    }

    final (versionOut, _) = await _runner.run('codex --version 2>&1');
    final (_, appServerExit) =
        await _runner.run('codex app-server --help 2>/dev/null');

    return CodexFound(
      path: path.trim(),
      version: versionOut.trim(),
      hasAppServer: appServerExit == 0,
    );
  }
}
