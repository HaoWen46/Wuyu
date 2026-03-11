/// Session — protocol layer above Transport.
///
/// Responsibilities:
///   1. Drive a background message pump that reads from the transport.
///   2. Correlate outbound requests with inbound responses by request ID.
///   3. Queue server-sent notifications for consumers.
///   4. Queue server-initiated requests (approvals) separately.
///   5. Execute the initialize/initialized handshake.
///
/// The Session does NOT know about SSH — it works with any Transport.
library;

import 'dart:async';
import 'dart:collection';

import 'protocol/jsonrpc.dart';
import 'transport.dart';

export 'protocol/jsonrpc.dart';
export 'transport.dart';

/// Thrown when the server returns a JSON-RPC error response.
final class SessionError implements Exception {
  final String message;
  final int code;

  SessionError(this.message, this.code);

  @override
  String toString() => 'SessionError[$code]: $message';
}

/// Stateful JSON-RPC session over a Transport.
///
/// Usage:
///   final session = Session(transport)..start();
///   final result = await session.initialize(clientInfo: {...});
final class Session {
  final Transport _transport;

  final _pending = <Object, Completer<Object?>>{};
  final _notifQueue = _AsyncQueue<JsonRpcNotification>();
  final _serverRequestQueue = _AsyncQueue<JsonRpcRequest>();
  int _nextId = 0;

  Session(this._transport);

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  /// Start the background message pump. Returns immediately.
  void start() {
    unawaited(_pump());
  }

  // ------------------------------------------------------------------
  // Client → Server
  // ------------------------------------------------------------------

  /// Send a JSON-RPC request and wait for the response.
  /// Throws [SessionError] if the server returns an error response.
  Future<Object?> request(String method, {Map<String, Object?>? params}) {
    final id = ++_nextId;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _transport.send(JsonRpcRequest(id: id, method: method, params: params));
    return completer.future;
  }

  /// Send a JSON-RPC notification (no response expected).
  void notify(String method, {Map<String, Object?>? params}) {
    _transport.send(JsonRpcNotification(method: method, params: params));
  }

  /// Respond to a server-initiated request (e.g. approval).
  void respond({required Object requestId, Object? result}) {
    _transport.send(JsonRpcResponse(id: requestId, result: result));
  }

  // ------------------------------------------------------------------
  // Server → Client (consuming)
  // ------------------------------------------------------------------

  /// Wait for the next server notification.
  Future<JsonRpcNotification> receiveNotification() => _notifQueue.get();

  /// Wait for the next server-initiated request.
  Future<JsonRpcRequest> receiveServerRequest() => _serverRequestQueue.get();

  // ------------------------------------------------------------------
  // Handshake
  // ------------------------------------------------------------------

  /// Perform the initialize/initialized handshake.
  ///
  /// Sends `initialize` request, awaits the server's response,
  /// then sends `initialized` notification to complete the handshake.
  Future<Object?> initialize({required Map<String, Object?> clientInfo}) async {
    final result = await request(
      'initialize',
      params: {'clientInfo': clientInfo},
    );
    notify('initialized');
    return result;
  }

  // ------------------------------------------------------------------
  // Internal pump
  // ------------------------------------------------------------------

  Future<void> _pump() async {
    while (true) {
      final msg = await _transport.receive();
      if (msg == null) {
        _cancelPending('transport closed');
        return;
      }
      _dispatch(msg);
    }
  }

  void _dispatch(Object msg) {
    if (msg is JsonRpcResponse) {
      final completer = _pending.remove(msg.id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(msg.result);
      }
    } else if (msg is JsonRpcErrorResponse) {
      final completer = _pending.remove(msg.id);
      if (completer != null && !completer.isCompleted) {
        completer.completeError(SessionError(msg.error.message, msg.error.code));
      }
    } else if (msg is JsonRpcNotification) {
      _notifQueue.add(msg);
    } else if (msg is JsonRpcRequest) {
      _serverRequestQueue.add(msg);
    }
  }

  void _cancelPending(String reason) {
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError(reason));
      }
    }
    _pending.clear();
  }
}

/// Async queue: add() immediately completes waiting get() calls, or buffers.
final class _AsyncQueue<T> {
  final _items = Queue<T>();
  final _waiters = Queue<Completer<T>>();

  void add(T item) {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(item);
    } else {
      _items.add(item);
    }
  }

  Future<T> get() {
    if (_items.isNotEmpty) return Future.value(_items.removeFirst());
    final c = Completer<T>();
    _waiters.add(c);
    return c.future;
  }
}
