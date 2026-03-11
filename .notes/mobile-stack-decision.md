# Mobile Stack Decision

## Decision: Flutter + dartssh2

### Why Flutter
- **dartssh2** (pure Dart, no native bindings) provides `SSHClient.execute()` → `SSHSession`
  with `stdout` as `Stream<Uint8List>` — maps directly to JSONL line-by-line processing
- One codebase for iOS + Android + macOS (desktop remote testing)
- Dart `Stream` + `LineSplitter` + `jsonDecode` is idiomatic for the JSONL pipeline
- **Flutter Server Box** uses dartssh2 in production (iOS/Android/desktop/TV) — proven path
- Dart AOT + Flutter Impeller (Metal/Vulkan) is fast enough for a chat UI

### Core JSONL pipeline in Dart

```dart
final session = await client.execute('codex app-server');

// Inbound: SSH stdout → JSONL lines → dispatch
session.stdout
    .cast<List<int>>()
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .listen((line) => dispatch(jsonDecode(line)));

// Outbound
session.stdin.add(utf8.encode('${jsonEncode(message)}\n'));
```

### dartssh2 facts
- 11,000 weekly downloads, 140 pub points, MIT, verified publisher (terminal.studio)
- v2.13.0 (released ~8 months ago)
- Host key verification via `onVerifyHostKey` callback (returns bool)
  - Must implement TOFU or `~/.ssh/known_hosts` parsing manually (no built-in)
  - `SSHKeyPair.fromPem()` supports RSA, ECDSA, Ed25519
- Pair with `flutter_secure_storage` for Keychain/Keystore, `local_auth` for Face ID/Touch ID

### Alternatives considered

| Option | Why not |
|--------|---------|
| Swift (iOS-only) | iOS-only, separate Android effort; use if going iOS-first intentionally |
| Kotlin Multiplatform | No pure-KMP SSH library, still needs per-platform native bridging |
| React Native | No maintained SSH library; `ssh2` requires heavy shimming |
| Native Android (Kotlin + Jetpack) | Android-only |

### If iOS-only later: Swift + Citadel
Citadel wraps SwiftNIO SSH (Apple, Swift 6, last release Nov 2025).
`executeCommandStream()` returns `AsyncSequence`. Maximum native iOS perf, native Keychain, Face ID.
Worth revisiting if Android support isn't needed.

## Prior Python exploration

The M0/M1 Python implementation (`src/wuyu/`) is a **protocol reference implementation**.
It validated:
- JSONL codec design (encode/decode, no jsonrpc field, field-presence discrimination)
- Session architecture (request/future correlation, notification queues, approval queue)
- asyncssh integration patterns

The Dart/Flutter implementation should mirror these designs. The Python code stays as
reference/testing tooling but is not the production app.

## References
- dartssh2: https://pub.dev/packages/dartssh2
- Flutter Server Box (example app): https://github.com/lollipopkit/flutter_server_box
- Citadel (Swift): https://github.com/orlandos-nl/Citadel
- SwiftNIO SSH: https://github.com/apple/swift-nio-ssh
