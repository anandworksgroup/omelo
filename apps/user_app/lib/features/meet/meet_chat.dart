import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../data/meet_repository.dart';

/// In-room chat: history, live messages, unread count.
class MeetChat extends ChangeNotifier {
  MeetChat(this._repo, this.interviewId);

  final MeetRepository _repo;
  final String interviewId;

  final List<MeetMessage> messages = [];
  int unread = 0;
  bool isOpen = false;
  bool loadFailed = false;
  bool sending = false;

  RealtimeChannel? _channel;
  bool _disposed = false;

  String? get myId => _repo.currentUserId;

  Future<void> start() async {
    _channel = _repo.watchMessages(interviewId, _add);
    try {
      final history = await _repo.messages(interviewId);
      for (final m in history) {
        _add(m, countUnread: false);
      }
      loadFailed = false;
    } catch (_) {
      loadFailed = true;
    }
    _notify();
  }

  void _add(MeetMessage m, {bool countUnread = true}) {
    if (messages.any((x) => x.id == m.id)) return;
    messages
      ..add(m)
      ..sort((a, b) => a.id.compareTo(b.id));
    if (countUnread && !isOpen && m.senderId != myId) unread++;
    _notify();
  }

  void setOpen(bool open) {
    isOpen = open;
    if (open) unread = 0;
    _notify();
  }

  /// Returns an error sentence, or null when sent.
  Future<String?> send(String text) async {
    if (text.trim().isEmpty) return null;
    sending = true;
    _notify();
    try {
      final m = await _repo.send(interviewId, text);
      if (m != null) _add(m, countUnread: false);
      return null;
    } catch (e) {
      return meetActionError(e);
    } finally {
      sending = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final c = _channel;
    if (c != null) _repo.unsubscribe(c);
    super.dispose();
  }
}

/// The chat itself — used as a side panel on wide screens and inside a
/// bottom sheet on phones.
class MeetChatPanel extends StatefulWidget {
  const MeetChatPanel({super.key, required this.chat, this.onClose});
  final MeetChat chat;
  final VoidCallback? onClose;

  @override
  State<MeetChatPanel> createState() => _MeetChatPanelState();
}

class _MeetChatPanelState extends State<MeetChatPanel> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text;
    if (t.trim().isEmpty) return;
    _text.clear();
    final err = await widget.chat.send(t);
    if (err != null && mounted) {
      _text.text = t;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _scrollToEndSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.chat,
      builder: (context, _) {
        final chat = widget.chat;
        if (chat.messages.length != _lastCount) {
          _lastCount = chat.messages.length;
          _scrollToEndSoon();
        }
        return Material(
          color: scheme.surface,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Chat',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    if (widget.onClose != null)
                      IconButton(
                        tooltip: 'Close chat',
                        icon: const Icon(Icons.close),
                        onPressed: widget.onClose,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Messages are seen by everyone in this interview.',
                  style:
                      TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              ),
              const Divider(height: 16),
              Expanded(
                child: chat.messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            chat.loadFailed
                                ? 'Could not load messages.'
                                : 'No messages yet. You can type here if '
                                    'the interviewer cannot hear you.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: chat.messages.length,
                        itemBuilder: (_, i) => _Bubble(
                          message: chat.messages[i],
                          mine: chat.messages[i].senderId == chat.myId,
                        ),
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _text,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: MeetMessage.maxLength,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: 'Type a message',
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        tooltip: 'Send',
                        iconSize: 24,
                        constraints:
                            const BoxConstraints(minWidth: 52, minHeight: 52),
                        onPressed: chat.sending ? null : _send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});
  final MeetMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = TimeOfDay.fromDateTime(message.sentAt).format(context);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${mine ? 'You' : (message.senderName ?? 'Interviewer')} · $t',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              SelectableText(message.body,
                  style: const TextStyle(fontSize: 15, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }
}
