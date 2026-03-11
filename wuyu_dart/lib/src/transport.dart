/// Abstract transport interface for the Codex App Server protocol.
///
/// Implementations: SshTransport (dartssh2), InMemoryTransport (tests).
/// The transport deals in decoded message objects, not raw bytes/lines —
/// JSONL parsing happens at the implementation layer.
library;

abstract interface class Transport {
  /// Send a message to the remote endpoint.
  /// Throws [StateError] if the transport is closed.
  void send(Object message);

  /// Receive the next incoming message.
  /// Returns null when the connection is closed (EOF).
  Future<Object?> receive();

  /// Close the connection.
  Future<void> close();

  /// Whether the transport is currently connected.
  bool get isConnected;
}
