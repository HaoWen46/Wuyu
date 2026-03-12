import 'package:wuyu_app/ssh/secure_kv.dart';

/// Persists SSH host key fingerprints for TOFU (Trust On First Use) verification.
///
/// Fingerprints are stored as lowercase hex strings keyed by `host_key:<host>:<port>`.
/// The caller is responsible for the trust decision on first connect — this class
/// is pure storage.
class HostKeyStore {
  final SecureKV _store;

  HostKeyStore(this._store);

  /// Returns the stored fingerprint hex for [host]:[port], or null if unknown.
  Future<String?> getFingerprint(String host, int port) {
    return _store.read(_key(host, port));
  }

  /// Persists [fingerprintBytes] (raw MD5, 16 bytes) for [host]:[port].
  Future<void> storeFingerprint(
      String host, int port, List<int> fingerprintBytes) {
    return _store.write(_key(host, port), _hexEncode(fingerprintBytes));
  }

  /// Removes the stored fingerprint for [host]:[port].
  Future<void> removeFingerprint(String host, int port) {
    return _store.delete(_key(host, port));
  }

  /// Formats [fingerprintBytes] as a colon-separated hex string for display.
  ///
  /// Example: `a1:b2:c3:d4:e5:f6:07:08:09:0a:0b:0c:0d:0e:0f:10`
  static String formatFingerprint(List<int> fingerprintBytes) {
    return fingerprintBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':');
  }

  static String _key(String host, int port) => 'host_key:$host:$port';

  static String _hexEncode(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
