import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:wuyu_app/ssh/secure_kv.dart';

/// Manages the device's Ed25519 SSH identity key.
///
/// Generates a key pair on first use, stores it as an OpenSSH PEM in
/// [SecureKV], and reconstructs it on subsequent calls.
class SshKeyService {
  static const _storageKey = 'ssh_device_key';

  final SecureKV _store;

  SshKeyService(this._store);

  /// Returns the device key pair, generating and persisting it if needed.
  Future<SSHKeyPair> getOrCreateKeyPair() async {
    final pem = await _store.read(_storageKey);
    if (pem != null) {
      return SSHKeyPair.fromPem(pem).first;
    }
    final keyPair = _generateEd25519();
    await _store.write(_storageKey, keyPair.toPem());
    return keyPair;
  }

  /// Returns the `authorized_keys` line for the device's public key.
  ///
  /// Example: `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... wuyu`
  Future<String> authorizedKeysLine() async {
    final keyPair = await getOrCreateKeyPair();
    return _encodeAuthorizedKey(keyPair);
  }

  static OpenSSHEd25519KeyPair _generateEd25519() {
    final signingKey = nacl.SigningKey.generate();
    return OpenSSHEd25519KeyPair(
      signingKey.verifyKey.asTypedList, // 32-byte public key
      signingKey.asTypedList, // 64-byte private key (seed + public)
      'wuyu',
    );
  }

  static String _encodeAuthorizedKey(SSHKeyPair keyPair) {
    final encoded = keyPair.toPublicKey().encode();
    final type = _readSshString(encoded);
    return '$type ${base64.encode(encoded)} wuyu';
  }

  // SSH wire format: 4-byte big-endian length + UTF-8 string (RFC 4251 §5).
  static String _readSshString(Uint8List bytes) {
    final len = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return utf8.decode(bytes.sublist(4, 4 + len));
  }
}
