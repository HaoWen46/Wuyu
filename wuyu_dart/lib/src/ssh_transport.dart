/// SSH-backed [Transport] implementation using dartssh2.
///
/// Use [SshTransport.connect] to open a real SSH connection to a remote host.
/// Use [SshTransport.fake] in tests to inject in-memory streams.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'codec.dart';
import 'transport.dart';

/// [Transport] backed by an SSH channel exec (dartssh2).
///
/// The SSH channel's stdout is transformed into a JSONL stream of decoded
/// messages. Each [send] call encodes the message and writes it to stdin.
class SshTransport implements Transport {
  final Future<void> Function() _closeCallback;
  final void Function(Uint8List) _write;
  bool _connected;

  // Async queue: items waiting to be consumed, and receivers waiting for items.
  final _items = Queue<Object?>();
  final _waiters = Queue<Completer<Object?>>();

  late final StreamSubscription<String> _lineSub;

  SshTransport._({
    required Stream<List<int>> stdout,
    required void Function(Uint8List) write,
    required Future<void> Function() onClose,
  })  : _write = write,
        _closeCallback = onClose,
        _connected = true {
    _lineSub = stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .listen(
          _onLine,
          onDone: _onEof,
        );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Factories

  /// Open an SSH connection to [host]:[port] and execute [command].
  ///
  /// [identities] enables public-key authentication.
  /// [onPasswordRequest] enables password authentication.
  /// [onVerifyHostKey] is called with the server's key type and MD5 fingerprint;
  /// return true to accept, false to reject. If null, all host keys are accepted
  /// (suitable for initial pairing flows handled at the UI layer).
  static Future<SshTransport> connect({
    required String host,
    int port = 22,
    required String username,
    List<SSHKeyPair>? identities,
    SSHPasswordRequestHandler? onPasswordRequest,
    SSHHostkeyVerifyHandler? onVerifyHostKey,
    String command = 'codex app-server',
    Duration? timeout,
  }) async {
    final socket = await SSHSocket.connect(host, port, timeout: timeout);
    final client = SSHClient(
      socket,
      username: username,
      identities: identities,
      onPasswordRequest: onPasswordRequest,
      onVerifyHostKey: onVerifyHostKey,
    );
    final session = await client.execute(command);
    return SshTransport._(
      stdout: session.stdout.cast<List<int>>(),
      write: session.stdin.add,
      onClose: () async {
        session.close();
        client.close();
        await client.done.catchError((_) {});
      },
    );
  }

  /// Create a transport backed by in-memory streams, for unit testing.
  ///
  /// [stdout] is the fake server-to-client byte stream.
  /// [write] receives encoded bytes for each [send] call.
  /// [onClose] is called when [close] is invoked.
  factory SshTransport.fake({
    required Stream<List<int>> stdout,
    required void Function(Uint8List) write,
    required Future<void> Function() onClose,
  }) {
    return SshTransport._(stdout: stdout, write: write, onClose: onClose);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Transport interface

  /// Send [message] to the remote endpoint, encoded as a JSONL line.
  /// Throws [StateError] if the transport is already closed.
  @override
  void send(Object message) {
    if (!_connected) throw StateError('SshTransport is closed');
    _write(utf8.encode(encode(message)));
  }

  /// Receive the next decoded message.
  /// Returns null when the stream reaches EOF (remote process exited).
  @override
  Future<Object?> receive() {
    if (_items.isNotEmpty) return Future.value(_items.removeFirst());
    if (!_connected) return Future.value(null);
    final completer = Completer<Object?>();
    _waiters.add(completer);
    return completer.future;
  }

  /// Close the SSH channel and the underlying client connection.
  @override
  Future<void> close() async {
    if (!_connected) return;
    _connected = false;
    await _lineSub.cancel();
    // Drain any pending waiters with null (EOF semantics).
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(null);
    }
    await _closeCallback();
  }

  @override
  bool get isConnected => _connected;

  // ──────────────────────────────────────────────────────────────────────────
  // Internal stream handling

  void _onLine(String line) {
    Object? msg;
    try {
      msg = decode(line);
    } on CodecError {
      return; // silently drop malformed lines
    }
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(msg);
    } else {
      _items.add(msg);
    }
  }

  void _onEof() {
    _connected = false;
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(null);
    }
  }
}
