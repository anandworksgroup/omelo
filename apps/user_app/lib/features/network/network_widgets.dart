import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/network_repository.dart';
import '../messages/inbox_providers.dart' show notificationsProvider;
import '../../core/ui.dart';

/// Shared pieces of the professional network: avatars, author rows, the
/// Follow and Connect buttons, and the report and block dialogs.

void networkSnack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(text)));
}

/// A person's photo or an organization's logo, with the first letter of the
/// name when there is no picture (or it fails to load — a broken image is
/// worse than an initial).
class NetworkAvatar extends ConsumerWidget {
  const NetworkAvatar({super.key, required this.author, this.radius = 22});

  final PostAuthor author;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final url = author.avatarUrl;
    final fallback = Text(
      author.initial,
      style: TextStyle(
        fontSize: radius * 0.85,
        fontWeight: FontWeight.w800,
        color: scheme.onPrimaryContainer,
      ),
    );

    return Semantics(
      label: author.name,
      child: ClipRRect(
        // Organizations are square-ish, people are round: the shape alone
        // says which kind of author this is.
        borderRadius: BorderRadius.circular(author.isOrganization ? 8 : radius),
        child: Container(
          width: radius * 2,
          height: radius * 2,
          color: scheme.primaryContainer,
          alignment: Alignment.center,
          child: url == null
              ? fallback
              : Image.network(
                  url,
                  width: radius * 2,
                  height: radius * 2,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(child: fallback),
                ),
        ),
      ),
    );
  }
}

/// Name, verified tick, and one line underneath — the row at the top of
/// every post, comment and network card.
class AuthorRow extends StatelessWidget {
  const AuthorRow({
    super.key,
    required this.author,
    this.secondary,
    this.trailing,
    this.radius = 22,
    this.onTap,
    this.dense = false,
  });

  final PostAuthor author;

  /// The headline, the time, or both — whatever the surface wants to say.
  final String? secondary;
  final Widget? trailing;
  final double radius;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = Row(
      children: [
        Flexible(
          child: Text(
            author.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: dense ? 14.5 : 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (author.verified) ...[
          const SizedBox(width: 5),
          const Icon(
            Icons.verified,
            size: 15,
            color: OmeloTheme.verified,
            semanticLabel: 'Verified',
          ),
        ],
      ],
    );

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NetworkAvatar(author: author, radius: radius),
        SizedBox(width: dense ? 10 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              name,
              if (secondary != null && secondary!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  secondary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: dense ? 12.5 : 13,
                    height: 1.3,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );

    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(padding: const EdgeInsets.all(2), child: body),
    );
  }
}

/// Follow or unfollow a person or an organization.
///
/// The button flips at once and flips back if the server refuses, so a tap
/// never feels dead on a slow network.
class FollowButton extends ConsumerStatefulWidget {
  const FollowButton({
    super.key,
    required this.author,
    this.following = false,
    this.onChanged,
    this.compact = false,
  });

  final PostAuthor author;
  final bool following;
  final void Function(bool following)? onChanged;
  final bool compact;

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  late bool _following = widget.following;
  bool _busy = false;

  @override
  void didUpdateWidget(FollowButton old) {
    super.didUpdateWidget(old);
    if (old.following != widget.following) _following = widget.following;
  }

  Future<void> _toggle() async {
    final want = !_following;
    setState(() {
      _following = want;
      _busy = true;
    });
    try {
      await ref
          .read(networkRepositoryProvider)
          .follow(widget.author.type, widget.author.id, want);
      widget.onChanged?.call(want);
    } catch (e) {
      if (!mounted) return;
      setState(() => _following = !want);
      networkSnack(context, networkError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _following ? 'Following' : 'Follow';
    final onPressed = _busy ? null : _toggle;
    if (_following) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.check, size: 18),
        label: Text(label),
        style: _style(),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: const Icon(Icons.add, size: 18),
      label: Text(label),
      style: _style(),
    );
  }

  ButtonStyle? _style() => widget.compact
      ? OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        )
      : null;
}

/// Ask to connect. Once asked, it says so instead of letting the worker
/// send the same request again.
class ConnectButton extends ConsumerStatefulWidget {
  const ConnectButton({
    super.key,
    required this.person,
    this.requested = false,
    this.connected = false,
    this.compact = false,
    this.onRequested,
  });

  final PostAuthor person;
  final bool requested;
  final bool connected;
  final bool compact;
  final VoidCallback? onRequested;

  @override
  ConsumerState<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends ConsumerState<ConnectButton> {
  late bool _requested = widget.requested;
  bool _busy = false;

  Future<void> _ask() async {
    final note = await askConnectionNote(context, widget.person);
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(networkRepositoryProvider)
          .requestConnection(
            widget.person.id,
            message: note.isEmpty ? null : note,
          );
      if (!mounted) return;
      setState(() => _requested = true);
      widget.onRequested?.call();
      networkSnack(context, 'Request sent to ${widget.person.name}.');
    } catch (e) {
      if (mounted) networkSnack(context, networkError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.connected) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.how_to_reg, size: 18),
        label: const Text('Connected'),
        style: _style(),
      );
    }
    if (_requested) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.schedule, size: 18),
        label: const Text('Requested'),
        style: _style(),
      );
    }
    return FilledButton.icon(
      onPressed: _busy ? null : _ask,
      icon: const Icon(Icons.person_add_alt, size: 18),
      label: const Text('Connect'),
      style: _style(),
    );
  }

  ButtonStyle? _style() => widget.compact
      ? OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        )
      : null;
}

/// The optional note on a connection request. Returns null when the worker
/// backed out, or the note (possibly empty) when they chose to send it.
Future<String?> askConnectionNote(BuildContext context, PostAuthor person) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Connect with ${person.name}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'You can add a short note saying how you know each other. It is '
            'optional.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            maxLength: kConnectionNoteMax,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'We worked the same site in Pune.',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Send request'),
        ),
      ],
    ),
  );
}

/// Pick a reason and say more. Returns null when the worker backed out.
Future<({ReportReason reason, String details})?> askReport(
  BuildContext context, {
  required String what,
}) {
  var reason = ReportReason.spam;
  final details = TextEditingController();
  return showDialog<({ReportReason reason, String details})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Report this $what'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Omelo reads every report. Tell us what is wrong and we take '
                'it from there.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 12),
              for (final r in ReportReason.values)
                RadioListTile<ReportReason>(
                  value: r,
                  groupValue: reason,
                  onChanged: (v) => setState(() => reason = v ?? reason),
                  title: Text(r.label, style: const TextStyle(fontSize: 14.5)),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              const SizedBox(height: 8),
              TextField(
                controller: details,
                maxLines: 3,
                minLines: 2,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Anything else we should know? (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop((reason: reason, details: details.text.trim())),
            child: const Text('Report'),
          ),
        ],
      ),
    ),
  );
}

/// Blocking is not undoable from the app, so it asks first and says what it
/// does.
Future<bool> confirmBlock(BuildContext context, PostAuthor author) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Block ${author.name}?'),
      content: Text(
        author.isOrganization
            ? 'You will not see this organization on Omelo, and it will not '
                  'see you. You can undo this in Settings.'
            : 'You will not see each other on Omelo. Any connection between '
                  'you is removed. You can undo this in Settings.',
        style: const TextStyle(fontSize: 14.5, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: OmeloTheme.danger),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Block'),
        ),
      ],
    ),
  );
  return yes ?? false;
}

/// One plain yes/no question, used for deleting a post or a comment and for
/// removing a connection.
Future<bool> confirmNetworkAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool danger = true,
}) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body, style: const TextStyle(fontSize: 14.5, height: 1.45)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: OmeloTheme.danger)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return yes ?? false;
}

/// An empty state that does not scroll, for use inside a list that already
/// does. [OmeloMessage] is a ListView, which cannot be nested.
class NetworkEmpty extends StatelessWidget {
  const NetworkEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 32),
      child: Column(
        children: [
          Icon(icon, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14.5, height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// Back arrow that lands somewhere real when the screen was opened from a
/// deeplink and there is nothing to pop.
Widget? networkBackButton(BuildContext context, String fallback) =>
    context.canPop()
    ? null
    : IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back',
        onPressed: () => context.go(fallback),
      );

/// Network notice types, as migration 72 added them.
const kNetworkNoticeTypes = <String>{
  'post_reaction',
  'post_comment',
  'post_share',
  'post_mention',
  'connection_request',
  'connection_update',
  'new_follower',
};

/// Runs [onNotice] whenever a network notification arrives, so a feed or a
/// network list on screen refreshes instead of showing stale counts.
void listenForNetworkNotices(WidgetRef ref, VoidCallback onNotice) {
  ref.listen<int>(
    notificationsProvider.select(
      (s) => s.items.where((n) => kNetworkNoticeTypes.contains(n.type)).length,
    ),
    (before, after) {
      if (before != null && after > before) onNotice();
    },
  );
}
