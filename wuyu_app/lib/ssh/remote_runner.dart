import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Runs a shell command on a remote host and returns its stdout + exit code.
abstract interface class RemoteRunner {
  Future<(String stdout, int exitCode)> run(String command);
}

/// Production [RemoteRunner] backed by an [SSHClient].
class SshRemoteRunner implements RemoteRunner {
  final SSHClient _client;

  SshRemoteRunner(this._client);

  @override
  Future<(String stdout, int exitCode)> run(String command) async {
    final session = await _client.execute(command);
    final bytes = await session.stdout
        .fold(BytesBuilder(copy: false), (b, chunk) => b..add(chunk))
        .then((b) => b.takeBytes());
    await session.done;
    return (utf8.decode(bytes), session.exitCode ?? -1);
  }
}
