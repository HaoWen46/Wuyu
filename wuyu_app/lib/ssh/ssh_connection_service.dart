import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:wuyu_app/ssh/host_key_store.dart';
import 'package:wuyu_app/ssh/ssh_key_service.dart';

/// Called on first connect to an unknown host (TOFU dialog).
///
/// [type] — key type, e.g. `'ssh-ed25519'`.
/// [displayFingerprint] — colon-separated MD5 hex for display, e.g.
/// `'a1:b2:c3:...'`.
/// Return true to trust and store, false to abort the connection.
typedef OnUnknownHostCallback = Future<bool> Function(
  String type,
  String displayFingerprint,
);

/// Opens authenticated SSH connections using the device key and TOFU host
/// verification.
class SshConnectionService {
  final SshKeyService _keyService;
  final HostKeyStore _hostKeyStore;

  SshConnectionService(this._keyService, this._hostKeyStore);

  /// Connects to [host]:[port] as [username].
  ///
  /// On first connect to a host, [onUnknownHost] is awaited to get user
  /// approval. On subsequent connects the stored fingerprint is compared;
  /// a mismatch aborts with [SSHHostkeyError] (possible MITM).
  Future<SSHClient> connect({
    required String host,
    required int port,
    required String username,
    required OnUnknownHostCallback onUnknownHost,
  }) async {
    final keyPair = await _keyService.getOrCreateKeyPair();
    final socket = await SSHSocket.connect(host, port);
    return SSHClient(
      socket,
      username: username,
      identities: [keyPair],
      onVerifyHostKey: (type, fingerprintBytes) =>
          verifyHostKey(host, port, type, fingerprintBytes, onUnknownHost),
    );
  }

  /// Implements TOFU host key verification logic.
  ///
  /// Exposed for testing — production code calls this via [connect].
  Future<bool> verifyHostKey(
    String host,
    int port,
    String type,
    Uint8List fingerprintBytes,
    OnUnknownHostCallback onUnknownHost,
  ) async {
    final stored = await _hostKeyStore.getFingerprint(host, port);
    final incoming = _hexEncode(fingerprintBytes);

    if (stored == null) {
      final display = HostKeyStore.formatFingerprint(fingerprintBytes);
      final trusted = await onUnknownHost(type, display);
      if (trusted) {
        await _hostKeyStore.storeFingerprint(host, port, fingerprintBytes);
      }
      return trusted;
    }

    // Known host — reject on mismatch (possible MITM).
    return stored == incoming;
  }

  static String _hexEncode(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
