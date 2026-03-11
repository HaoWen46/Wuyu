# Dev Environment

Notes on the machine where this project is developed. Saves re-discovery time across sessions.

## Dart SDK

Installed at `/tmp2/b11902156/dart-sdk/` (v3.11.2, stable).

Not in PATH by default. Before running any dart command:
```bash
export PATH="/tmp2/b11902156/dart-sdk/bin:$PATH"
```

Or add to shell rc. The `wuyu_dart` tests:
```bash
export PATH="/tmp2/b11902156/dart-sdk/bin:$PATH"
cd /tmp2/b11902156/Projects/Wuyu/wuyu_dart
dart test      # 50 tests
dart analyze
```

## Flutter SDK

Installed at `/tmp2/b11902156/flutter/` (v3.32.0, stable, bundles Dart 3.8.0).

```bash
export PATH="/tmp2/b11902156/flutter/bin:/tmp2/b11902156/dart-sdk/bin:$PATH"
cd /tmp2/b11902156/Projects/Wuyu/wuyu_app
flutter analyze
flutter test
```

Note: Flutter bundles its own Dart (3.8.0). The standalone `/tmp2/b11902156/dart-sdk` (3.11.2) is used only for `wuyu_dart`. They coexist fine with both in PATH (flutter's dart takes precedence inside `wuyu_app`).

## Shell limitations

Standard GNU coreutils are **not in PATH** in this shell environment:
- `head`, `tail`, `grep`, `find`, `sed`, `awk` — all missing
- Use Claude Code's built-in tools instead: Read, Glob, Grep
- In Bash commands, avoid piping through these; run commands that produce complete output directly

## No sudo

Cannot install system packages via pacman/apt/etc. All tooling must be user-local.
