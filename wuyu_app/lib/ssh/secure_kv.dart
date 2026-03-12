/// Minimal key-value store interface over a secure storage backend.
///
/// The production implementation wraps [FlutterSecureStorage].
/// Tests inject an in-memory fake.
abstract interface class SecureKV {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}
