import 'package:test/test.dart';

import 'package:wuyu_dart/src/codec.dart';

void main() {
  group('encode', () {
    test('request serializes method, id, and params', () {
      final msg = JsonRpcRequest(id: 1, method: 'initialize', params: {'a': 'b'});
      final line = encode(msg);
      expect(line, '{"id":1,"method":"initialize","params":{"a":"b"}}\n');
    });

    test('request with int id', () {
      final msg = JsonRpcRequest(id: 0, method: 'thread/start');
      final line = encode(msg);
      expect(line, '{"id":0,"method":"thread/start"}\n');
    });

    test('request with string id', () {
      final msg = JsonRpcRequest(id: 'req-1', method: 'turn/start');
      final line = encode(msg);
      expect(line, '{"id":"req-1","method":"turn/start"}\n');
    });

    test('notification has method but no id', () {
      final msg = JsonRpcNotification(method: 'initialized');
      final line = encode(msg);
      expect(line, '{"method":"initialized"}\n');
    });

    test('notification with params', () {
      final msg = JsonRpcNotification(method: 'initialized', params: {'x': 1});
      final line = encode(msg);
      expect(line, '{"method":"initialized","params":{"x":1}}\n');
    });

    test('response serializes id and result', () {
      final msg = JsonRpcResponse(id: 1, result: {'userAgent': 'codex/1.0'});
      final line = encode(msg);
      expect(line, '{"id":1,"result":{"userAgent":"codex/1.0"}}\n');
    });

    test('error response serializes id and error object', () {
      final msg = JsonRpcErrorResponse(
        id: 1,
        error: JsonRpcError(code: -32601, message: 'Method not found'),
      );
      final line = encode(msg);
      expect(
        line,
        '{"id":1,"error":{"code":-32601,"message":"Method not found"}}\n',
      );
    });

    test('omits null params from request', () {
      final msg = JsonRpcRequest(id: 1, method: 'thread/list');
      expect(encode(msg), isNot(contains('"params"')));
    });

    test('omits null params from notification', () {
      final msg = JsonRpcNotification(method: 'initialized');
      expect(encode(msg), isNot(contains('"params"')));
    });

    test('omits null result from response', () {
      final msg = JsonRpcResponse(id: 1);
      expect(encode(msg), isNot(contains('"result"')));
    });
  });

  group('decode', () {
    test('id+method → request', () {
      final msg = decode('{"id":1,"method":"initialize","params":{"a":1}}\n');
      expect(msg, isA<JsonRpcRequest>());
      final req = msg as JsonRpcRequest;
      expect(req.id, 1);
      expect(req.method, 'initialize');
      expect(req.params, {'a': 1});
    });

    test('method only → notification', () {
      final msg = decode('{"method":"initialized"}\n');
      expect(msg, isA<JsonRpcNotification>());
      final notif = msg as JsonRpcNotification;
      expect(notif.method, 'initialized');
      expect(notif.params, isNull);
    });

    test('id+result → response', () {
      final msg = decode('{"id":1,"result":{"userAgent":"codex/1.0"}}');
      expect(msg, isA<JsonRpcResponse>());
      final resp = msg as JsonRpcResponse;
      expect(resp.id, 1);
      expect(resp.result, {'userAgent': 'codex/1.0'});
    });

    test('id+error → error response', () {
      final msg = decode('{"id":1,"error":{"code":-32601,"message":"Not found"}}');
      expect(msg, isA<JsonRpcErrorResponse>());
      final err = msg as JsonRpcErrorResponse;
      expect(err.id, 1);
      expect(err.error.code, -32601);
      expect(err.error.message, 'Not found');
    });

    test('string id is preserved', () {
      final msg = decode('{"id":"req-1","method":"thread/start"}');
      final req = msg as JsonRpcRequest;
      expect(req.id, 'req-1');
    });

    test('response with null result', () {
      final msg = decode('{"id":0,"result":null}');
      expect(msg, isA<JsonRpcResponse>());
      final resp = msg as JsonRpcResponse;
      expect(resp.result, isNull);
    });

    test('throws CodecError on empty line', () {
      expect(() => decode(''), throwsA(isA<CodecError>()));
      expect(() => decode('   '), throwsA(isA<CodecError>()));
    });

    test('throws CodecError on invalid JSON', () {
      expect(() => decode('{bad json}'), throwsA(isA<CodecError>()));
    });

    test('throws CodecError on JSON array', () {
      expect(() => decode('[1,2,3]'), throwsA(isA<CodecError>()));
    });

    test('throws CodecError on unclassifiable message', () {
      expect(() => decode('{"result":"orphan"}'), throwsA(isA<CodecError>()));
    });

    test('encode/decode round-trip for request', () {
      final original = JsonRpcRequest(id: 42, method: 'thread/start', params: {'cwd': '/home'});
      final decoded = decode(encode(original));
      expect(decoded, isA<JsonRpcRequest>());
      final req = decoded as JsonRpcRequest;
      expect(req.id, 42);
      expect(req.method, 'thread/start');
      expect(req.params, {'cwd': '/home'});
    });

    test('encode/decode round-trip for notification', () {
      final original = JsonRpcNotification(method: 'initialized', params: {'v': 2});
      final decoded = decode(encode(original));
      expect(decoded, isA<JsonRpcNotification>());
      final n = decoded as JsonRpcNotification;
      expect(n.method, 'initialized');
      expect(n.params, {'v': 2});
    });
  });
}
