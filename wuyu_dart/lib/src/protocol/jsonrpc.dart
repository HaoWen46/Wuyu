/// JSON-RPC message types for the Codex App Server protocol.
///
/// The Codex App Server uses a non-standard JSON-RPC 2.0 variant — it omits
/// the "jsonrpc": "2.0" field. Messages are classified by field presence:
///   - id + method  → Request
///   - method only  → Notification
///   - id + result  → Response
///   - id + error   → ErrorResponse
library;

/// A request from client to server (or server to client for approvals).
/// Expects a response with the same id.
final class JsonRpcRequest {
  final Object id; // String or int
  final String method;
  final Map<String, Object?>? params;

  const JsonRpcRequest({required this.id, required this.method, this.params});
}

/// A fire-and-forget message — no id, no response expected.
final class JsonRpcNotification {
  final String method;
  final Map<String, Object?>? params;

  const JsonRpcNotification({required this.method, this.params});
}

/// Successful response to a request.
final class JsonRpcResponse {
  final Object id; // String or int
  final Object? result;

  const JsonRpcResponse({required this.id, this.result});
}

/// Error detail within an error response.
final class JsonRpcError {
  final int code;
  final String message;
  final Object? data;

  const JsonRpcError({required this.code, required this.message, this.data});
}

/// Error response to a request.
final class JsonRpcErrorResponse {
  final Object id; // String or int
  final JsonRpcError error;

  const JsonRpcErrorResponse({required this.id, required this.error});
}

// Well-known error codes
const errorServerOverloaded = -32001;
const errorParseError = -32700;
const errorInvalidRequest = -32600;
const errorMethodNotFound = -32601;
