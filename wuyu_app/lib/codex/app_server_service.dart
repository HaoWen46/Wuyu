import 'package:dartssh2/dartssh2.dart';
import 'package:wuyu_dart/wuyu_dart.dart';

/// Launches the Codex App Server over SSH and performs the protocol handshake.
class AppServerService {
  /// Opens a `codex app-server` exec channel on [client] and returns the
  /// transport. The transport and [client] are closed together.
  static Future<SshTransport> openTransport(SSHClient client) async {
    final sshSession = await client.execute('codex app-server');
    return SshTransport.fromSession(sshSession, client);
  }

  /// Performs the initialize/initialized handshake over [transport] and
  /// returns the ready [Session].
  ///
  /// Exposed separately from [openTransport] so it can be tested with any
  /// [Transport] (including [SshTransport.fake]).
  static Future<Session> handshake(Transport transport) async {
    final session = Session(transport)..start();
    await session.initialize(
      clientInfo: {'name': 'wuyu', 'version': '0.1.0'},
    );
    return session;
  }
}
