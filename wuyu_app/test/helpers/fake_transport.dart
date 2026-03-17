import 'package:wuyu_dart/wuyu_dart.dart';

/// In-memory [Transport] for unit tests.
///
/// Plays back a fixed list of incoming messages. Returns null (transport
/// closed) once the list is exhausted.
final class FakeTransport implements Transport {
  final List<Object?> _incoming;
  final List<Object> sent = [];
  int _idx = 0;
  bool _connected = true;

  FakeTransport({List<Object?>? incoming}) : _incoming = incoming ?? [];

  @override
  void send(Object message) => sent.add(message);

  @override
  Future<Object?> receive() async {
    if (_idx >= _incoming.length) {
      _connected = false;
      return null;
    }
    await Future.microtask(() {});
    return _incoming[_idx++];
  }

  @override
  Future<void> close() async => _connected = false;

  @override
  bool get isConnected => _connected;
}
