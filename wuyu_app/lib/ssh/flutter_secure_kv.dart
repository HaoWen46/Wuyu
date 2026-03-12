import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wuyu_app/ssh/secure_kv.dart';

/// [SecureKV] backed by [FlutterSecureStorage] (iOS Keychain / Android Keystore).
class FlutterSecureKv implements SecureKV {
  final FlutterSecureStorage _storage;

  const FlutterSecureKv([
    this._storage = const FlutterSecureStorage(),
  ]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
