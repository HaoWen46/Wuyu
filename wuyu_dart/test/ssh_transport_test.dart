import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wuyu_dart/src/ssh_transport.dart';
import 'package:wuyu_dart/src/protocol/jsonrpc.dart';

/// Push a JSONL line into a fake stdout StreamController.
void pushLine(StreamController<Uint8List> ctrl, String line) {
  ctrl.add(Uint8List.fromList(utf8.encode('$line\n')));
}

void main() {
  group('SshTransport', () {
    late StreamController<Uint8List> stdoutCtrl;
    late List<Uint8List> stdinChunks;
    late SshTransport transport;

    setUp(() {
      stdoutCtrl = StreamController<Uint8List>();
      stdinChunks = [];
      transport = SshTransport.fake(
        stdout: stdoutCtrl.stream.cast<List<int>>(),
        write: stdinChunks.add,
        onClose: () async {},
      );
    });

    tearDown(() async {
      await transport.close();
      if (!stdoutCtrl.isClosed) await stdoutCtrl.close();
    });

    test('isConnected is true after construction', () {
      expect(transport.isConnected, isTrue);
    });

    test('receive() decodes a notification from stdout', () async {
      pushLine(stdoutCtrl, '{"method":"initialized"}');
      final msg = await transport.receive();
      expect(msg, isA<JsonRpcNotification>());
      expect((msg as JsonRpcNotification).method, equals('initialized'));
    });

    test('receive() decodes a request from stdout', () async {
      pushLine(stdoutCtrl, '{"id":1,"method":"thread/start"}');
      final msg = await transport.receive();
      expect(msg, isA<JsonRpcRequest>());
      expect((msg as JsonRpcRequest).method, equals('thread/start'));
    });

    test('receive() queues multiple messages in arrival order', () async {
      pushLine(stdoutCtrl, '{"method":"first"}');
      pushLine(stdoutCtrl, '{"method":"second"}');
      // Yield to the event loop so stream events are processed.
      await Future.microtask(() {});
      final msg1 = await transport.receive();
      final msg2 = await transport.receive();
      expect((msg1 as JsonRpcNotification).method, equals('first'));
      expect((msg2 as JsonRpcNotification).method, equals('second'));
    });

    test('receive() waits for next message if none queued', () async {
      final future = transport.receive();
      await Future.microtask(() {});
      pushLine(stdoutCtrl, '{"method":"late"}');
      final msg = await future;
      expect((msg as JsonRpcNotification).method, equals('late'));
    });

    test('send() encodes notification to stdin as JSONL', () {
      transport.send(const JsonRpcNotification(method: 'initialized'));
      expect(stdinChunks, hasLength(1));
      expect(utf8.decode(stdinChunks.single), equals('{"method":"initialized"}\n'));
    });

    test('send() encodes request with id and method to stdin', () {
      transport.send(const JsonRpcRequest(id: 1, method: 'initialize'));
      expect(stdinChunks, hasLength(1));
      expect(utf8.decode(stdinChunks.single), equals('{"id":1,"method":"initialize"}\n'));
    });

    test('receive() returns null on EOF (stdout closed)', () async {
      await stdoutCtrl.close();
      final msg = await transport.receive();
      expect(msg, isNull);
    });

    test('isConnected is false after close()', () async {
      await transport.close();
      expect(transport.isConnected, isFalse);
    });

    test('send() throws StateError after close()', () async {
      await transport.close();
      expect(
        () => transport.send(const JsonRpcNotification(method: 'test')),
        throwsStateError,
      );
    });

    test('malformed lines are silently dropped', () async {
      pushLine(stdoutCtrl, 'not valid json at all');
      pushLine(stdoutCtrl, '{"method":"good"}');
      await Future.microtask(() {});
      final msg = await transport.receive();
      expect((msg as JsonRpcNotification).method, equals('good'));
    });

    test('blank lines in stdout are ignored', () async {
      stdoutCtrl.add(Uint8List.fromList(utf8.encode('\n\n')));
      pushLine(stdoutCtrl, '{"method":"after-blanks"}');
      await Future.microtask(() {});
      final msg = await transport.receive();
      expect((msg as JsonRpcNotification).method, equals('after-blanks'));
    });
  });
}
