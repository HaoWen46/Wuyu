import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuyu_app/ssh/ssh_key_service.dart';

import 'fake_secure_kv.dart';

void main() {
  group('SshKeyService', () {
    late FakeSecureKV store;
    late SshKeyService service;

    setUp(() {
      store = FakeSecureKV();
      service = SshKeyService(store);
    });

    test('getOrCreateKeyPair generates and stores a key on first call',
        () async {
      expect(await store.read('ssh_device_key'), isNull);

      final keyPair = await service.getOrCreateKeyPair();

      expect(keyPair, isA<OpenSSHEd25519KeyPair>());
      expect(await store.read('ssh_device_key'), isNotNull);
    });

    test('getOrCreateKeyPair returns the same key on subsequent calls',
        () async {
      final keyPair1 = await service.getOrCreateKeyPair();
      final keyPair2 = await service.getOrCreateKeyPair();

      // Same public key bytes means same identity
      expect(
        keyPair1.toPublicKey().encode(),
        equals(keyPair2.toPublicKey().encode()),
      );
    });

    test('getOrCreateKeyPair loads key from pre-existing store entry', () async {
      // Simulate a key that was stored in a previous session
      final original = await service.getOrCreateKeyPair();
      final originalPubKey = original.toPublicKey().encode();

      // New service instance, same store
      final service2 = SshKeyService(store);
      final loaded = await service2.getOrCreateKeyPair();

      expect(loaded.toPublicKey().encode(), equals(originalPubKey));
    });

    test('authorizedKeysLine starts with ssh-ed25519', () async {
      final line = await service.authorizedKeysLine();
      expect(line, startsWith('ssh-ed25519 '));
    });

    test('authorizedKeysLine ends with wuyu comment', () async {
      final line = await service.authorizedKeysLine();
      expect(line, endsWith(' wuyu'));
    });

    test('authorizedKeysLine middle part is valid base64', () async {
      final line = await service.authorizedKeysLine();
      final parts = line.split(' ');
      expect(parts.length, 3);
      // Should not throw
      final decoded = base64.decode(parts[1]);
      // SSH wire format for Ed25519 public key is > 32 bytes (includes type prefix)
      expect(decoded.length, greaterThan(32));
    });

    test('two services generate different keys', () async {
      final service2 = SshKeyService(FakeSecureKV());
      final key1 = await service.getOrCreateKeyPair();
      final key2 = await service2.getOrCreateKeyPair();
      expect(
        key1.toPublicKey().encode(),
        isNot(equals(key2.toPublicKey().encode())),
      );
    });
  });
}
