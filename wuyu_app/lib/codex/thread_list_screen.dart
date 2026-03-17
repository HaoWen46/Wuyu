import 'package:flutter/material.dart';
import 'package:wuyu_app/codex/chat_screen.dart';
import 'package:wuyu_app/codex/thread_service.dart';

/// Lists existing threads for a project and lets the user resume one
/// or start a new one.
///
/// Fetches `thread/list` once on enter. Pull-to-refresh re-fetches.
/// No polling — the list is only as live as the last fetch.
class ThreadListScreen extends StatefulWidget {
  final ThreadService service;
  final String cwd;

  const ThreadListScreen({
    super.key,
    required this.service,
    required this.cwd,
  });

  @override
  State<ThreadListScreen> createState() => _ThreadListScreenState();
}

class _ThreadListScreenState extends State<ThreadListScreen> {
  List<ThreadSummary>? _threads;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _threads = null;
      _error = null;
    });
    try {
      final threads = await widget.service.listThreads();
      if (mounted) setState(() => _threads = threads);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _openThread(String? threadId) {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ChatScreen(
        service: widget.service,
        cwd: widget.cwd,
        threadId: threadId,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Threads'),
        backgroundColor: cs.inversePrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openThread(null),
        icon: const Icon(Icons.add),
        label: const Text('New thread'),
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: _fetch,
                  child: const Text('Retry'),
                ),
              ],
            ),
          Expanded(child: _buildBody(cs)),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_threads == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final threads = _threads ?? [];
    if (threads.isEmpty) {
      return Center(
        child: Text(
          'No threads yet.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.builder(
        itemCount: threads.length,
        itemBuilder: (context, i) => _buildRow(threads[i], cs),
      ),
    );
  }

  Widget _buildRow(ThreadSummary thread, ColorScheme cs) {
    final dt = thread.createdAt.toLocal();
    final label =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return ListTile(
      title: Text(
        thread.id,
        style: const TextStyle(fontFamily: 'monospace'),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openThread(thread.id),
    );
  }
}
