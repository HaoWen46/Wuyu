# dartssh2 API Notes

Gotchas discovered while implementing `SshTransport` in `wuyu_dart`.
Version: dartssh2 2.13.0.

## Key API shapes

```dart
// 1. Open socket
final socket = await SSHSocket.connect(host, port, timeout: timeout);

// 2. Create client — note: identities: (plural), not identityKey:
final client = SSHClient(
  socket,
  username: username,
  identities: identities,            // List<SSHKeyPair>?, optional
  onPasswordRequest: handler,        // SSHPasswordRequestHandler?
  onVerifyHostKey: verifyHandler,    // SSHHostkeyVerifyHandler?
);

// 3. Execute remote command
final session = await client.execute(command);

// 4. Streams
session.stdout   // Stream<Uint8List>  — NOT Stream<List<int>>
session.stdin    // StreamSink<Uint8List>

// Cast stdout for compatibility with utf8.decoder:
session.stdout.cast<List<int>>()

// Pass stdin.add as a tear-off (type: void Function(Uint8List)):
session.stdin.add   // ← tear-off works directly
```

## Host key verification handler type

```dart
// SSHHostkeyVerifyHandler = FutureOr<bool> Function(String type, Uint8List fingerprint)
// The fingerprint is MD5 (not SHA256) — 16 bytes raw, hex-encode for display.
// Return true to accept, false to reject.
// If onVerifyHostKey is null, ALL host keys are accepted.
```

## Key pair types

```dart
// Public-key auth
List<SSHKeyPair> identities = [someKeyPair];

// Generate Ed25519 key pair (for device keys):
final keyPair = SSHKeyPair.generateEd25519();  // returns SSHKeyPair
// Export public key as authorized_keys line:
keyPair.toPublicKey().toAuthorizedKey();       // → "ssh-ed25519 AAAA... wuyu"
```

## Lifecycle

```dart
// Close order matters:
session.close();          // void — close the channel
client.close();           // void — close the client
await client.done.catchError((_) {});  // wait for teardown, swallow errors
// (client.done can throw if the connection died uncleanly)
```

## stdin type mismatch workaround

`session.stdin` is `StreamSink<Uint8List>`, not `StreamSink<List<int>>`.
Avoid storing it as a typed sink — instead, capture the `add` tear-off:

```dart
final void Function(Uint8List) write = session.stdin.add;
```

This is what `SshTransport._()` does: stores `write` as a callback, so the
internal constructor and `SshTransport.fake()` share the same interface without
a type mismatch.

## Testing without a real SSH server

`SshTransport.fake()` injects in-memory streams:

```dart
final stdoutCtrl = StreamController<Uint8List>();
final stdinChunks = <Uint8List>[];

final transport = SshTransport.fake(
  stdout: stdoutCtrl.stream.cast<List<int>>(),
  write: stdinChunks.add,
  onClose: () async {},
);

// Push server → client bytes:
stdoutCtrl.add(Uint8List.fromList(utf8.encode('{"method":"initialized"}\n')));

// Read client → server bytes:
utf8.decode(stdinChunks.single);
```
