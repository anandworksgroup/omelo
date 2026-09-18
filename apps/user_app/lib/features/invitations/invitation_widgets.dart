import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/invitations.dart';

/// A company logo, or its first letter when there is none (or it fails).
class CompanyAvatar extends StatelessWidget {
  const CompanyAvatar({
    super.key,
    required this.name,
    this.logoUrl,
    this.size = 44,
  });

  final String name;
  final String? logoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Text(letter,
          style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.w800,
              color: scheme.onPrimaryContainer)),
    );
    final url = logoUrl;
    if (url == null || !url.startsWith('http')) {
      return ExcludeSemantics(child: fallback);
    }
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}

/// Company name with the verified tick.
class CompanyName extends StatelessWidget {
  const CompanyName(
    this.name, {
    super.key,
    required this.verified,
    this.fontSize = 15,
    this.showWord = false,
  });

  final String name;
  final bool verified;
  final double fontSize;

  /// Also write "Verified" next to the tick.
  final bool showWord;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(name,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700)),
        ),
        if (verified) ...[
          const SizedBox(width: 5),
          Icon(Icons.verified,
              size: fontSize + 1,
              color: OmeloTheme.verified,
              semanticLabel: 'Verified employer'),
          if (showWord) ...[
            const SizedBox(width: 3),
            const Text('Verified',
                style: TextStyle(
                    fontSize: 12.5,
                    color: OmeloTheme.verified,
                    fontWeight: FontWeight.w700)),
          ],
        ],
      ],
    );
  }
}

/// Status chip for an invitation.
class InvitationStatusPill extends StatelessWidget {
  const InvitationStatusPill(this.status, {super.key});
  final InvitationStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color fg, Color bg, IconData icon) = switch (status) {
      InvitationStatus.pending => (
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
          Icons.mark_email_unread_outlined
        ),
      InvitationStatus.applied => (
          OmeloTheme.verified,
          OmeloTheme.verified.withValues(alpha: 0.12),
          Icons.check_circle_outline
        ),
      InvitationStatus.declined => (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerHighest,
          Icons.do_not_disturb_on_outlined
        ),
      InvitationStatus.withdrawn ||
      InvitationStatus.expired ||
      InvitationStatus.closed =>
        (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerHighest,
          Icons.schedule_outlined
        ),
    };
    return OmeloPill(invitationStatusLabel(status),
        icon: icon, color: fg, background: bg);
  }
}
