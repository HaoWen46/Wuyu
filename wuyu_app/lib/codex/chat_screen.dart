import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wuyu_app/codex/agent_message_accumulator.dart';
import 'package:wuyu_app/codex/events.dart';
import 'package:wuyu_app/codex/thread_service.dart';

// ---------------------------------------------------------------------------
// Internal item model
// ---------------------------------------------------------------------------

sealed class _Item {
  const _Item();
}

final class _UserItem extends _Item {
  final String text;
  const _UserItem(this.text);
}

/// An agent message item whose text is held in [AgentMessageAccumulator].
final class _AgentItem extends _Item {
  final String itemId;
  const _AgentItem(this.itemId);
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Chat screen for a single Codex App Server thread.
///
/// Calls [ThreadService.startThread] on init, then listens to [ThreadService.events]
/// and renders user messages (right) and streaming agent responses (left).
class ChatScreen extends StatefulWidget {
  final ThreadService service;

  /// The working directory passed to `thread/start` and `turn/start`.
  final String cwd;

  /// If non-null, resume this existing thread instead of starting a new one.
  ///
  /// Note: only new events are delivered after resume — prior message history
  /// is not replayed. History hydration via `thread/read` is M5 work.
  final String? threadId;

  const ChatScreen({
    super.key,
    required this.service,
    required this.cwd,
    this.threadId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _items = <_Item>[];
  final _acc = AgentMessageAccumulator();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  String? _threadId;
  String? _error;
  bool _turnRunning = false;
  late final StreamSubscription<AppServerEvent> _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.service.events.listen(
      _onEvent,
      onError: (Object e) {
        if (mounted) setState(() => _error = e.toString());
      },
      onDone: () {
        if (mounted) setState(() => _error = 'Connection closed.');
      },
    );
    _initThread();
  }

  @override
  void dispose() {
    _sub.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initThread() async {
    try {
      if (widget.threadId != null) {
        await widget.service.resumeThread(widget.threadId!);
        if (mounted) setState(() => _threadId = widget.threadId);
      } else {
        final id = await widget.service.startThread(cwd: widget.cwd);
        if (mounted) setState(() => _threadId = id);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _onEvent(AppServerEvent event) {
    setState(() {
      switch (event) {
        case TurnStartedEvent():
          _turnRunning = true;
        case AgentMessageDeltaEvent():
          if (!_acc.itemIds.contains(event.itemId)) {
            _items.add(_AgentItem(event.itemId));
          }
          _acc.apply(event);
        case TurnCompletedEvent():
          _turnRunning = false;
        case _:
          break;
      }
    });
    _scrollToBottom();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _threadId == null || _turnRunning) return;
    _controller.clear();
    setState(() {
      _items.add(_UserItem(text));
      _turnRunning = true;
    });
    _scrollToBottom();
    try {
      await widget.service.startTurn(
        threadId: _threadId!,
        text: text,
        cwd: widget.cwd,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _turnRunning = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && mounted) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_threadId == null
            ? 'Connecting…'
            : widget.threadId != null
                ? 'Resume · $_threadId'
                : 'Thread · $_threadId'),
        backgroundColor: cs.inversePrimary,
        actions: [
          if (_turnRunning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(child: _buildMessageList(cs)),
          _buildInput(cs),
        ],
      ),
    );
  }

  Widget _buildMessageList(ColorScheme cs) {
    if (_threadId == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          'Send a message to start.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _items.length,
      itemBuilder: (context, i) => _buildItem(_items[i], cs),
    );
  }

  Widget _buildItem(_Item item, ColorScheme cs) {
    return switch (item) {
      _UserItem(:final text) => _bubble(
          text: text,
          align: CrossAxisAlignment.end,
          color: cs.primaryContainer,
          textColor: cs.onPrimaryContainer,
        ),
      _AgentItem(:final itemId) => _bubble(
          text: _acc.textFor(itemId),
          align: CrossAxisAlignment.start,
          color: cs.surfaceContainerHighest,
          textColor: cs.onSurface,
        ),
    };
  }

  Widget _bubble({
    required String text,
    required CrossAxisAlignment align,
    required Color color,
    required Color textColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(18),
            ),
            child: text.isEmpty
                ? SizedBox(
                    width: 40,
                    height: 14,
                    child: LinearProgressIndicator(
                      color: textColor.withAlpha(120),
                      backgroundColor: textColor.withAlpha(30),
                    ),
                  )
                : Text(text, style: TextStyle(color: textColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(ColorScheme cs) {
    final canSend = _threadId != null && !_turnRunning;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: canSend,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                minLines: 1,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: canSend ? 'Message…' : 'Waiting for agent…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: canSend ? _send : null,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
