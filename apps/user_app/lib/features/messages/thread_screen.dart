import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/messaging_repository.dart';
import 'inbox_providers.dart';

/// `/messages/:id` — one job conversation with an employer.
class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen>
    with WidgetsBindingObserver {
  late final MessagingRepository _repo;
  final _composer = TextEditingController();
  final _focus = FocusNode();

  Conversation? _conversation;
  List<ChatMessage> _messages = const [];
  bool _loading = true;
  bool _notFound = false;
  bool _failed = false;
  bool _sending = false;

  RealtimeChannel? _channel;
  Timer? _poll;
  Timer? _readDebounce;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(messagingRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    _composer.addListener(_onTyping);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _readDebounce?.cancel();
    final c = _channel;
    if (c != null) _repo.unsubscribe(c);
    _composer.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _conversation != null) {
      _refetch();
    }
  }

  void _onTyping() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
      _notFound = false;
    });
    try {
      final c = await _repo.conversation(widget.conversationId);
      if (!mounted) return;
      if (c == null) {
        setState(() {
          _loading = false;
          _notFound = true;
        });
        return;
      }
      final msgs = await _repo.messages(c.id);
      if (!mounted) return;
      setState(() {
        _conversation = c;
        _messages = msgs;
        _loading = false;
      });
      _subscribe(c.id);
      _markRead();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _subscribe(String id) {
    final old = _channel;
    if (old != null) _repo.unsubscribe(old);
    _channel = _repo.watchThread(id, _onRealtime, onTrouble: _refetch);
    // Realtime can drop without telling us; refetch now and then.
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refetch());
  }

  void _onRealtime(ChatMessage m) {
    if (!mounted || m.conversationId != widget.conversationId) return;
    setState(() => _messages = Messaging.merge(_messages, m));
    if (!m.isMine && !m.isRead) _markRead();
  }

  Future<void> _refetch() async {
    final c = _conversation;
    if (c == null) return;
    try {
      final msgs = await _repo.messages(c.id);
      if (!mounted) return;
      setState(() => _messages = msgs);
      if (Messaging.unreadFromEmployer(msgs) > 0) _markRead();
    } catch (_) {}
  }

  /// Debounced so a burst of messages is one call.
  void _markRead() {
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 500), () async {
      final n = await _repo.markRead(widget.conversationId);
      if (!mounted) return;
      if (n > 0) {
        final now = DateTime.now();
        setState(() {
          _messages = [
            for (final m in _messages)
              m.isMine || m.isRead
                  ? m
                  : ChatMessage(
                      id: m.id,
                      conversationId: m.conversationId,
                      senderPersonId: m.senderPersonId,
                      senderType: m.senderType,
                      body: m.body,
                      sentAt: m.sentAt,
                      readAt: now,
                    ),
          ];
        });
      }
      ref.read(unreadMessagesProvider.notifier).refresh();
      ref.read(notificationsProvider.notifier).refresh();
    });
  }

  Future<void> _send() async {
    final c = _conversation;
    final text = _composer.text;
    if (c == null || _sending) return;
    final problem = Messaging.validate(text);
    if (problem != null) {
      _snack(problem);
      return;
    }
    setState(() => _sending = true);
    try {
      await _repo.send(c.id, text);
      _composer.clear();
      await _refetch();
    } catch (e) {
      _snack(messagingError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/messages');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _conversation;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: _back,
        ),
        titleSpacing: 0,
        title: c == null
            ? const Text('Messages')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.companyOrEmployer,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    c.jobOrSubject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
        actions: [
          if (c?.applicationId != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () =>
                    context.push('/applications/${c!.applicationId}'),
                icon: const Icon(Icons.assignment_outlined),
                label: const Text('Application'),
              ),
            ),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_notFound || _failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ContentWidth.reading(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _notFound
                      ? 'We could not find this conversation.'
                      : 'Could not load messages. Check your internet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _notFound ? () => context.go('/messages') : _load,
                  child: Text(_notFound ? 'All messages' : 'Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(child: _thread(context)),
        _composerBar(context),
      ],
    );
  }

  Widget _thread(BuildContext context) {
    if (_messages.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 16),
        children: const [
          ContentWidth.reading(
            child: Text(
              'No messages yet. Say hello, or ask the employer a question '
              'about the job.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15.5, height: 1.45),
            ),
          ),
        ],
      );
    }

    final now = DateTime.now();
    final seenId = Messaging.seenMessageId(_messages);
    // Newest at the bottom, list anchored to the bottom (reverse).
    final items = <Widget>[];
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final prev = i == 0 ? null : _messages[i - 1];
      final newDay = prev == null ||
          !DateUtils.isSameDay(prev.sentAt, m.sentAt);
      if (newDay) items.add(_DayDivider(Messaging.dayLabel(m.sentAt, now)));
      items.add(_Bubble(m: m, seen: m.id == seenId));
    }

    return ListView.builder(
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: items.length,
      itemBuilder: (_, i) =>
          ContentWidth.reading(child: items[items.length - 1 - i]),
    );
  }

  Widget _composerBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final length = _composer.text.trim().length;
    final tooLong = length > ChatMessage.maxLength;
    final canSend = length > 0 && !tooLong && !_sending;

    return Material(
      color: scheme.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: ContentWidth.reading(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    // Allow a little over so the counter can explain; the
                    // hard stop is a bit past the limit.
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(
                          ChatMessage.maxLength + 200),
                    ],
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Write a message',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      counterText: length > ChatMessage.maxLength - 200
                          ? '$length / ${ChatMessage.maxLength}'
                          : null,
                      counterStyle: TextStyle(
                          color: tooLong ? OmeloTheme.danger : null),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 52,
                  height: 52,
                  child: IconButton.filled(
                    tooltip: 'Send',
                    onPressed: canSend ? _send : null,
                    icon: _sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Icon(Icons.send),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant)),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m, required this.seen});
  final ChatMessage m;
  final bool seen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = m.isMine;
    final bg = mine ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = mine ? scheme.onPrimary : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(mine ? 18 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SelectableText(
                      m.body,
                      style: TextStyle(fontSize: 16, height: 1.35, color: fg),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      Messaging.bubbleTime(m.sentAt),
                      style: TextStyle(
                          fontSize: 12, color: fg.withValues(alpha: 0.75)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (seen)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Text('Seen',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}
