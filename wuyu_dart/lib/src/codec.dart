/// JSONL codec for the Codex App Server protocol.
///
/// Wire format: newline-delimited JSON, one object per line.
/// No HTTP headers, no Content-Length framing, no "jsonrpc":"2.0" field.
///
/// Encoding: message → compact JSON + '\n'
/// Decoding: JSONL line → discriminated message variant
library;

import 'dart:convert';

import 'protocol/jsonrpc.dart';

export 'protocol/jsonrpc.dart';

/// Thrown when a message cannot be encoded or decoded.
final class CodecError implements Exception {
  final String message;
  const CodecError(this.message);

  @override
  String toString() => 'CodecError: $message';
}

/// Serialize a JSON-RPC message to a JSONL line (with trailing newline).
/// Omits null optional fields (params, result).
String encode(Object message) {
  final Map<String, Object?> data;

  if (message is JsonRpcRequest) {
    data = {
      'id': message.id,
      'method': message.method,
      if (message.params != null) 'params': message.params,
    };
  } else if (message is JsonRpcNotification) {
    data = {
      'method': message.method,
      if (message.params != null) 'params': message.params,
    };
  } else if (message is JsonRpcResponse) {
    data = {
      'id': message.id,
      if (message.result != null) 'result': message.result,
    };
  } else if (message is JsonRpcErrorResponse) {
    data = {
      'id': message.id,
      'error': {
        'code': message.error.code,
        'message': message.error.message,
        if (message.error.data != null) 'data': message.error.data,
      },
    };
  } else {
    throw CodecError('unknown message type: ${message.runtimeType}');
  }

  return '${jsonEncode(data)}\n';
}

/// Parse a single JSONL line into a message variant.
/// Throws [CodecError] if the line is not valid JSON or cannot be classified.
Object decode(String line) {
  line = line.trim();
  if (line.isEmpty) throw const CodecError('empty line');

  final Object? parsed;
  try {
    parsed = jsonDecode(line);
  } on FormatException catch (e) {
    throw CodecError('invalid JSON: $e');
  }

  if (parsed is! Map) {
    throw CodecError('expected JSON object, got ${parsed.runtimeType}');
  }

  final data = parsed.cast<String, Object?>();
  return _classify(data);
}

Object _classify(Map<String, Object?> data) {
  final hasId = data.containsKey('id');
  final hasMethod = data.containsKey('method');
  final hasResult = data.containsKey('result');
  final hasError = data.containsKey('error');

  if (hasId && hasError) {
    final e = (data['error'] as Map).cast<String, Object?>();
    return JsonRpcErrorResponse(
      id: data['id']!,
      error: JsonRpcError(
        code: e['code'] as int,
        message: e['message'] as String,
        data: e['data'],
      ),
    );
  }

  if (hasId && hasResult) {
    return JsonRpcResponse(id: data['id']!, result: data['result']);
  }

  if (hasId && hasMethod) {
    final params = data['params'];
    return JsonRpcRequest(
      id: data['id']!,
      method: data['method'] as String,
      params: params != null ? (params as Map).cast<String, Object?>() : null,
    );
  }

  if (hasMethod && !hasId) {
    final params = data['params'];
    return JsonRpcNotification(
      method: data['method'] as String,
      params: params != null ? (params as Map).cast<String, Object?>() : null,
    );
  }

  // id with no method/result/error — treat as null result response
  if (hasId) {
    return JsonRpcResponse(id: data['id']!);
  }

  throw CodecError('cannot classify message: $data');
}
