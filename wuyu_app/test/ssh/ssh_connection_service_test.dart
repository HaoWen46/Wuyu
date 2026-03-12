import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wuyu_app/ssh/host_key_store.dart';
import 'package:wuyu_app/ssh/ssh_connection_service.dart';
import 'package:wuyu_app/ssh/ssh_key_service.dart';

import 'fake_secure_kv.dart';

void main() {
  late SshConnectionService svc;
  late HostKeyStore hostKeyStore;

  // 16-byte MD5 fingerprint and its expected hex/display representations.
  final fp = Uint8List.fromList(List.generate(16, (i) => i));
  final fpHex = List.generate(16, (i) => i.toRadixString(16).padLeft(2, '0')).join();
  final fpDisplay = List.generate(16, (i) => i.toRadixString(16).padLeft(2, '0')).join(':');

  setUp(() {
    final kv = FakeSecureKV();
    hostKeyStore = HostKeyStore(kv);
    svc = SshConnectionService(SshKeyService(FakeSecureKV()), hostKeyStore);
  });

  group('verifyHostKey', () {
    test('unknown host — user trusts — stores fingerprint and returns true',
        () async {
      var called = false;
      final result = await svc.verifyHostKey(
        'ws8', 22, 'ssh-ed25519', fp,
        (type, display) async {
          called = true;
          expect(type, 'ssh-ed25519');
          expect(display, fpDisplay);
          return true;
        },
      );

      expect(result, isTrue);
      expect(called, isTrue);
      expect(await hostKeyStore.getFingerprint('ws8', 22), fpHex);
    });

    test('unknown host — user rejects — does not store and returns false',
        () async {
      final result = await svc.verifyHostKey(
        'ws8', 22, 'ssh-ed25519', fp,
        (_, __) async => false,
      );

      expect(result, isFalse);
      expect(await hostKeyStore.getFingerprint('ws8', 22), isNull);
    });

    test('known host — fingerprint matches — returns true without callback',
        () async {
      await hostKeyStore.storeFingerprint('ws8', 22, fp);

      var called = false;
      final result = await svc.verifyHostKey(
        'ws8', 22, 'ssh-ed25519', fp,
        (_, __) async { called = true; return true; },
      );

      expect(result, isTrue);
      expect(called, isFalse);
    });

    test('known host — fingerprint changed — returns false without callback',
        () async {
      await hostKeyStore.storeFingerprint('ws8', 22, fp);

      final differentFp = Uint8List.fromList(List.filled(16, 0xff));
      var called = false;
      final result = await svc.verifyHostKey(
        'ws8', 22, 'ssh-ed25519', differentFp,
        (_, __) async { called = true; return true; },
      );

      expect(result, isFalse);
      expect(called, isFalse);
    });

    test('host isolation — different hosts stored independently', () async {
      await svc.verifyHostKey('ws8', 22, 'ssh-ed25519', fp, (_, __) async => true);

      final differentFp = Uint8List.fromList(List.filled(16, 0xab));
      final result = await svc.verifyHostKey(
        'ws9', 22, 'ssh-ed25519', differentFp,
        (_, __) async => true,
      );

      expect(result, isTrue);
      expect(await hostKeyStore.getFingerprint('ws8', 22), fpHex);
    });
  });
}
