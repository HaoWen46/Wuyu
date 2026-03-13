import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:wuyu_app/codex/app_server_service.dart';
import 'package:wuyu_app/codex/chat_screen.dart';
import 'package:wuyu_app/codex/thread_service.dart';
import 'package:wuyu_app/ssh/flutter_secure_kv.dart';
import 'package:wuyu_app/ssh/host_key_store.dart';
import 'package:wuyu_app/ssh/ssh_connection_service.dart';
import 'package:wuyu_app/ssh/ssh_key_service.dart';

/// Development / smoke-test screen: fill in SSH details, tap Connect,
/// and land in [ChatScreen] backed by a live Codex App Server session.
///
/// This is not the production UX (see M4 for project management); it exists
/// to validate the full stack end-to-end on a real device.
class DevConnectScreen extends StatefulWidget {
  const DevConnectScreen({super.key});

  @override
  State<DevConnectScreen> createState() => _DevConnectScreenState();
}

class _DevConnectScreenState extends State<DevConnectScreen> {
  final _hostCtrl = TextEditingController(text: 'localhost');
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController(text: 'student');
  final _cwdCtrl = TextEditingController(text: '/tmp');

  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _cwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final kv = const FlutterSecureKv();
      final keyService = SshKeyService(kv);
      final hostKeyStore = HostKeyStore(kv);
      final connService = SshConnectionService(keyService, hostKeyStore);

      final client = await connService.connect(
        host: _hostCtrl.text.trim(),
        port: int.parse(_portCtrl.text.trim()),
        username: _userCtrl.text.trim(),
        onUnknownHost: _promptTrust,
      );

      final transport = await AppServerService.openTransport(client);
      final session = await AppServerService.handshake(transport);
      final svc = ThreadService(session);

      if (!mounted) {
        client.close();
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            service: svc,
            cwd: _cwdCtrl.text.trim(),
          ),
        ),
      );
    } on SSHAuthAbortError catch (e) {
      if (mounted) setState(() => _error = 'Auth aborted: $e');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<bool> _promptTrust(String type, String fingerprint) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unknown Host'),
        content: Text(
          'Key type: $type\nFingerprint: $fingerprint\n\nTrust and connect?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Trust'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('无域 — Dev Connect'),
        backgroundColor: cs.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _hostCtrl,
              decoration: const InputDecoration(
                labelText: 'Host',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portCtrl,
              decoration: const InputDecoration(
                labelText: 'Port',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cwdCtrl,
              decoration: const InputDecoration(
                labelText: 'Working directory (cwd)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: cs.error),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _connecting ? null : _connect,
              child: _connecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
