import 'package:test/test.dart';

import 'package:wuyu_dart/src/transport.dart';
import 'package:wuyu_dart/src/protocol/jsonrpc.dart';

/// A minimal in-memory transport for testing the interface contract.
final class FakeTransport implements Transport {
  final List<Object> sent = [];
  final List<Object> _incoming;
  int _idx = 0;
  bool _closed = false;

  FakeTransport({List<Object>? incoming}) : _incoming = incoming ?? [];

  @override
  void send(Object message) {
    if (_closed) throw StateError('transport is closed');
    sent.add(message);
  }

  @override
  Future<Object?> receive() async {
    if (_idx >= _incoming.length) {
      _closed = true;
      return null; // EOF
    }
    return _incoming[_idx++];
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  @override
  bool get isConnected => !_closed;
}

void main() {
  group('Transport interface', () {
    test('FakeTransport implements Transport', () {
      final t = FakeTransport();
      expect(t, isA<Transport>());
    });

    test('send enqueues messages', () {
      final t = FakeTransport();
      final msg = JsonRpcNotification(method: 'initialized');
      t.send(msg);
      expect(t.sent, hasLength(1));
      expect(t.sent.first, same(msg));
    });

    test('receive returns messages in order', () async {
      final a = JsonRpcNotification(method: 'a');
      final b = JsonRpcNotification(method: 'b');
      final t = FakeTransport(incoming: [a, b]);

      expect(await t.receive(), same(a));
      expect(await t.receive(), same(b));
    });

    test('receive returns null at EOF', () async {
      final t = FakeTransport(incoming: []);
      expect(await t.receive(), isNull);
    });

    test('isConnected is true initially', () {
      final t = FakeTransport();
      expect(t.isConnected, isTrue);
    });

    test('isConnected is false after close', () async {
      final t = FakeTransport();
      await t.close();
      expect(t.isConnected, isFalse);
    });

    test('send throws after close', () async {
      final t = FakeTransport();
      await t.close();
      expect(
        () => t.send(JsonRpcNotification(method: 'x')),
        throwsStateError,
      );
    });
  });
}
