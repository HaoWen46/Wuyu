import 'package:flutter_test/flutter_test.dart';
import 'package:wuyu_app/ssh/host_key_store.dart';

import 'fake_secure_kv.dart';

void main() {
  group('HostKeyStore', () {
    late FakeSecureKV store;
    late HostKeyStore hostKeyStore;

    final host = 'example.com';
    const port = 22;
    final fingerprint = List<int>.generate(16, (i) => i);

    setUp(() {
      store = FakeSecureKV();
      hostKeyStore = HostKeyStore(store);
    });

    test('getFingerprint returns null for unknown host', () async {
      expect(await hostKeyStore.getFingerprint(host, port), isNull);
    });

    test('storeFingerprint and getFingerprint round-trip', () async {
      await hostKeyStore.storeFingerprint(host, port, fingerprint);
      final stored = await hostKeyStore.getFingerprint(host, port);
      expect(stored, equals('000102030405060708090a0b0c0d0e0f'));
    });

    test('different host/port combinations are stored independently', () async {
      final fp1 = List<int>.filled(16, 0xaa);
      final fp2 = List<int>.filled(16, 0xbb);

      await hostKeyStore.storeFingerprint('host1.example.com', 22, fp1);
      await hostKeyStore.storeFingerprint('host2.example.com', 22, fp2);

      expect(await hostKeyStore.getFingerprint('host1.example.com', 22),
          equals('aa' * 16));
      expect(await hostKeyStore.getFingerprint('host2.example.com', 22),
          equals('bb' * 16));
    });

    test('different ports on same host are stored independently', () async {
      final fp1 = List<int>.filled(16, 0x01);
      final fp2 = List<int>.filled(16, 0x02);

      await hostKeyStore.storeFingerprint(host, 22, fp1);
      await hostKeyStore.storeFingerprint(host, 2222, fp2);

      expect(await hostKeyStore.getFingerprint(host, 22), equals('01' * 16));
      expect(
          await hostKeyStore.getFingerprint(host, 2222), equals('02' * 16));
    });

    test('removeFingerprint removes the entry', () async {
      await hostKeyStore.storeFingerprint(host, port, fingerprint);
      await hostKeyStore.removeFingerprint(host, port);
      expect(await hostKeyStore.getFingerprint(host, port), isNull);
    });

    test('removeFingerprint is a no-op for unknown host', () async {
      // Should not throw
      await hostKeyStore.removeFingerprint('unknown.example.com', 22);
    });
  });

  group('HostKeyStore.formatFingerprint', () {
    test('formats bytes as colon-separated hex', () {
      final bytes = List<int>.generate(16, (i) => i);
      expect(
        HostKeyStore.formatFingerprint(bytes),
        equals('00:01:02:03:04:05:06:07:08:09:0a:0b:0c:0d:0e:0f'),
      );
    });

    test('pads single-digit hex values', () {
      expect(HostKeyStore.formatFingerprint([1, 2, 3]), equals('01:02:03'));
    });
  });
}
