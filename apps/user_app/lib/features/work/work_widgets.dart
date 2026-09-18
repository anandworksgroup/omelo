import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/work_repository.dart';
import '../messages/inbox_providers.dart' show notificationsProvider;

export '../../core/theme.dart' show OmeloPill;
export '../representations/representation_widgets.dart'
    show RepresentationMessage;

void showWorkSnack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Back arrow that still works when the screen was opened from a link (no
/// page underneath).
Widget? workBackButton(BuildContext context, String fallback) =>
    context.canPop()
    ? null
    : IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back',
        onPressed: () => context.go(fallback),
      );

/// Reloads the work lists whenever a work or shift notice arrives.
void listenForWorkNotices(WidgetRef ref) {
  ref.listen<int>(
    notificationsProvider.select(
      (s) => s.items
          .where((n) => n.type == 'shift_update' || n.type == 'work_update')
          .length,
    ),
    (_, __) => invalidateWork(ref),
  );
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

enum WorkTone { good, waiting, neutral, warning }

class WorkPill extends StatelessWidget {
  const WorkPill(this.label, {super.key, this.tone = WorkTone.neutral, this.icon});
  final String label;
  final WorkTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color fg, Color bg) = switch (tone) {
      WorkTone.good => (
        OmeloTheme.verified,
        OmeloTheme.verified.withValues(alpha: 0.12),
      ),
      WorkTone.waiting => (scheme.onPrimaryContainer, scheme.primaryContainer),
      WorkTone.warning => (
        OmeloTheme.warning,
        OmeloTheme.warning.withValues(alpha: 0.12),
      ),
      WorkTone.neutral => (
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      ),
    };
    return OmeloPill(label, icon: icon, color: fg, background: bg);
  }
}

WorkTone assignmentTone(Assignment a, DateTime now) {
  if (a.isOfferOpenAt(now)) return WorkTone.waiting;
  return switch (a.status) {
    AssignmentStatus.active || AssignmentStatus.accepted => WorkTone.good,
    AssignmentStatus.completed => WorkTone.good,
    AssignmentStatus.paused => WorkTone.warning,
    _ => WorkTone.neutral,
  };
}

WorkTone timesheetTone(TimesheetStatus s) => switch (s) {
  TimesheetStatus.draft => WorkTone.waiting,
  TimesheetStatus.rejected => WorkTone.warning,
  TimesheetStatus.approved || TimesheetStatus.locked => WorkTone.good,
  _ => WorkTone.neutral,
};

WorkTone earningTone(EarningStatus s) => switch (s) {
  EarningStatus.paid => WorkTone.good,
  EarningStatus.failed => WorkTone.warning,
  EarningStatus.calculated => WorkTone.neutral,
  _ => WorkTone.waiting,
};

WorkTone leaveTone(LeaveStatus s) => switch (s) {
  LeaveStatus.requested => WorkTone.waiting,
  LeaveStatus.approved => WorkTone.good,
  LeaveStatus.rejected => WorkTone.warning,
  LeaveStatus.cancelled => WorkTone.neutral,
};

/// A titled block on a detail screen.
class WorkSection extends StatelessWidget {
  const WorkSection({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

/// Icon, label and value on one line (wrapping when long).
class WorkInfoRow extends StatelessWidget {
  const WorkInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 15.5, height: 1.35),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A soft coloured note box ("Late arrival recorded — …").
class WorkNote extends StatelessWidget {
  const WorkNote(this.text, {super.key, this.tone = WorkTone.neutral, this.icon});
  final String text;
  final WorkTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color fg, Color bg) = switch (tone) {
      WorkTone.good => (
        OmeloTheme.verified,
        OmeloTheme.verified.withValues(alpha: 0.10),
      ),
      WorkTone.warning => (
        OmeloTheme.warning,
        OmeloTheme.warning.withValues(alpha: 0.10),
      ),
      WorkTone.waiting => (
        scheme.onPrimaryContainer,
        scheme.primaryContainer.withValues(alpha: 0.6),
      ),
      WorkTone.neutral => (
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.info_outline, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Verified by Omelo" — finished work that now counts as verified work
/// history on the worker's profile.
class VerifiedWorkBanner extends StatelessWidget {
  const VerifiedWorkBanner({super.key});

  @override
  Widget build(BuildContext context) => const WorkNote(
    'Verified by Omelo. This job is now on your work history as verified '
    'experience.',
    tone: WorkTone.good,
    icon: Icons.verified,
  );
}

/// Opens the phone's dialler.
Future<void> callNumber(BuildContext context, String phone) async {
  final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
  final ok = await launchUrl(Uri(scheme: 'tel', path: clean));
  if (!ok && context.mounted) {
    showWorkSnack(context, 'Could not open the phone. The number is $phone.');
  }
}

// ---------------------------------------------------------------------------
// Check in / check out
// ---------------------------------------------------------------------------

/// The big Check in / Check out button for one shift, with its state.
class CheckInPanel extends ConsumerStatefulWidget {
  const CheckInPanel({super.key, required this.shift, required this.now});
  final WorkShift shift;
  final DateTime now;

  @override
  ConsumerState<CheckInPanel> createState() => _CheckInPanelState();
}

class _CheckInPanelState extends ConsumerState<CheckInPanel> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.shift;
    final st = checkInState(s, widget.now);
    final btn = checkInButton(st, s, widget.now);
    final scheme = Theme.of(context).colorScheme;
    final review = attendanceReviewLine(s.attendance);

    final Widget main;
    if (btn.action != null) {
      final checkOut = btn.action == 'check_out';
      main = SizedBox(
        height: 60,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: checkOut ? scheme.tertiary : null,
            foregroundColor: checkOut ? scheme.onTertiary : null,
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          onPressed: _busy
              ? null
              : () => _run(
                  () => checkOut
                      ? checkOutFlow(context, ref, s)
                      : checkInFlow(context, ref, s),
                ),
          icon: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Icon(checkOut ? Icons.logout : Icons.login, size: 26),
          label: Text(btn.label),
        ),
      );
    } else {
      final done = st.phase == CheckInPhase.done;
      main = Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: done
              ? OmeloTheme.verified.withValues(alpha: 0.10)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              switch (st.phase) {
                CheckInPhase.done => Icons.check_circle,
                CheckInPhase.notOpenYet => Icons.schedule,
                CheckInPhase.supervisor => Icons.badge_outlined,
                CheckInPhase.cancelled => Icons.event_busy_outlined,
                CheckInPhase.onLeave => Icons.beach_access_outlined,
                _ => Icons.info_outline,
              },
              color: done ? OmeloTheme.verified : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                btn.label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: done ? OmeloTheme.verified : null,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        main,
        if (btn.detail != null) ...[
          const SizedBox(height: 6),
          Text(
            btn.detail!,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (st.phase == CheckInPhase.open && s.checkInMethod == 'qr') ...[
          const SizedBox(height: 6),
          Text(
            'Have the 6-digit code from your supervisor ready.',
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
          ),
        ],
        if (review != null) ...[
          const SizedBox(height: 8),
          WorkNote(
            review,
            tone: s.attendance!.needsReview
                ? WorkTone.waiting
                : WorkTone.neutral,
            icon: Icons.rate_review_outlined,
          ),
        ],
      ],
    );
  }
}

/// Check in for [s] the way its employer set up: on the app, with the
/// supervisor's code, or at the site (location asked only then).
Future<void> checkInFlow(
  BuildContext context,
  WidgetRef ref,
  WorkShift s,
) async {
  String? code;
  Position? pos;
  switch (s.checkInMethod) {
    case 'employer':
      showWorkSnack(context, 'Your supervisor records your arrival.');
      return;
    case 'qr':
      code = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const ShiftCodeSheet(),
      );
      if (code == null) return;
    case 'geofence':
      if (!context.mounted) return;
      pos = await _locationForCheckIn(context);
      if (pos == null) return;
  }
  try {
    await ref
        .read(workRepositoryProvider)
        .checkIn(
          s.shiftWorkerId,
          method: s.checkInMethod,
          lat: pos?.latitude,
          lng: pos?.longitude,
          code: code,
        );
  } catch (e) {
    if (context.mounted) showWorkSnack(context, workError(e));
    return;
  }
  // Reload to learn whether arrival was late (recorded for review).
  invalidateWork(ref);
  String message = 'Checked in. Have a good shift.';
  try {
    final fresh = await ref.read(myWorkProvider.future);
    final me = fresh.where((x) => x.shiftWorkerId == s.shiftWorkerId);
    final line = me.isEmpty ? null : attendanceReviewLine(me.first.attendance);
    if (line != null) message = 'Checked in. $line.';
  } catch (_) {}
  if (context.mounted) showWorkSnack(context, message);
}

/// Check out, asking first when it is well before the end of the shift.
Future<void> checkOutFlow(
  BuildContext context,
  WidgetRef ref,
  WorkShift s,
) async {
  final now = DateTime.now();
  if (now.isBefore(s.endsAt.subtract(const Duration(minutes: 15)))) {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finish early?'),
        content: Text(
          'Your shift ends at ${clockAt(s.endsAt, s.timezone)}. If you check '
          'out now, the early finish is recorded for your supervisor to '
          'review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Check out'),
          ),
        ],
      ),
    );
    if (go != true) return;
  }
  try {
    final r = await ref.read(workRepositoryProvider).checkOut(s.shiftWorkerId);
    invalidateWork(ref);
    if (context.mounted) showWorkSnack(context, checkOutMessage(r));
  } catch (e) {
    if (context.mounted) showWorkSnack(context, workError(e));
  }
}

/// Location, asked for only for work that checks you in at the site.
Future<Position?> _locationForCheckIn(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Share your location to check in'),
      content: const Text(
        'This work checks that you are at the site. Your location is used '
        'once, only for this check-in.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Share location'),
        ),
      ],
    ),
  );
  if (ok != true) return null;
  const off =
      'Location is off. Turn it on to check in here, or ask your supervisor '
      'to record your arrival.';
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (context.mounted) showWorkSnack(context, off);
      return null;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      if (context.mounted) showWorkSnack(context, off);
      return null;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      showWorkSnack(
        context,
        'Could not find your location. Try again, or ask your supervisor.',
      );
    }
    return null;
  }
}

/// Type the 6-digit code the supervisor shows at the site.
class ShiftCodeSheet extends StatefulWidget {
  const ShiftCodeSheet({super.key});

  @override
  State<ShiftCodeSheet> createState() => _ShiftCodeSheetState();
}

class _ShiftCodeSheetState extends State<ShiftCodeSheet> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = isValidShiftCode(_code.text);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Enter the check-in code',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ask your supervisor for the 6-digit code for this shift.',
            style: TextStyle(fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: 10,
            ),
            decoration: const InputDecoration(
              hintText: '000000',
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (isValidShiftCode(_code.text)) {
                Navigator.pop(context, _code.text.trim());
              }
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: ok
                ? () => Navigator.pop(context, _code.text.trim())
                : null,
            child: const Text('Check in'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shift cards
// ---------------------------------------------------------------------------

/// Today's shift: the time in the site's zone, who and where, and the big
/// button.
class TodayShiftCard extends StatelessWidget {
  const TodayShiftCard({super.key, required this.shift, required this.now});
  final WorkShift shift;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = shift;
    final scheme = Theme.of(context).colorScheme;
    final zone = zoneNote(s.startsAt, s.timezone);
    final name = shiftNameLine(s);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => context.push(shiftRoute(s.shiftId)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shiftDayLabel(s.startsAt, s.timezone, now),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                        Text(
                          shiftTimeRange(s.startsAt, s.endsAt, s.timezone),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (zone != null)
                          Text(
                            zone,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          s.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          shiftEmployerLine(s),
                          style: TextStyle(
                            fontSize: 14.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (s.location != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 18,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  s.location!,
                                  style: const TextStyle(fontSize: 14.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (name.isNotEmpty || s.isCancelled) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (name.isNotEmpty) OmeloPill(name),
                              if (s.isCancelled)
                                const WorkPill(
                                  'Cancelled',
                                  tone: WorkTone.warning,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: scheme.onSurfaceVariant,
                    semanticLabel: 'Shift details',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            CheckInPanel(shift: s, now: now),
          ],
        ),
      ),
    );
  }
}

/// A coming shift, one line each.
class ShiftTile extends StatelessWidget {
  const ShiftTile({super.key, required this.shift, required this.now});
  final WorkShift shift;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = shift;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(shiftRoute(s.shiftId)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    shiftDayLabel(s.startsAt, s.timezone, now),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shiftTimeRange(s.startsAt, s.endsAt, s.timezone),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          decoration: s.isCancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      Text(
                        '${s.title} · ${shiftEmployerLine(s)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (s.isCancelled) ...[
                        const SizedBox(height: 4),
                        const WorkPill('Cancelled', tone: WorkTone.warning),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An extra shift offered to me: Accept / Decline.
class ShiftOfferCard extends ConsumerStatefulWidget {
  const ShiftOfferCard({super.key, required this.shift, required this.now});
  final WorkShift shift;
  final DateTime now;

  @override
  ConsumerState<ShiftOfferCard> createState() => _ShiftOfferCardState();
}

class _ShiftOfferCardState extends ConsumerState<ShiftOfferCard> {
  bool _busy = false;

  Future<void> _answer(bool accept) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(workRepositoryProvider)
          .respondToShift(widget.shift.shiftWorkerId, accept);
      invalidateWork(ref);
      if (mounted) {
        showWorkSnack(
          context,
          accept
              ? 'Shift accepted. It is in your list now.'
              : 'You said no to this shift.',
        );
      }
    } catch (e) {
      invalidateWork(ref);
      if (mounted) showWorkSnack(context, workError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.shift;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => context.push(shiftRoute(s.shiftId)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const WorkPill(
                    'Extra shift offered',
                    tone: WorkTone.waiting,
                    icon: Icons.add_alarm,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${shiftDayLabel(s.startsAt, s.timezone, widget.now)} · '
                    '${shiftTimeRange(s.startsAt, s.endsAt, s.timezone)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    s.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    [
                      shiftEmployerLine(s),
                      ?s.location,
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (s.pay.rate != null)
                    Text(
                      payLine(s.pay),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _answer(false),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _answer(true),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Assignment card
// ---------------------------------------------------------------------------

class AssignmentCard extends StatelessWidget {
  const AssignmentCard({super.key, required this.assignment, required this.now});
  final Assignment assignment;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    final scheme = Theme.of(context).colorScheme;
    final dates = datesLine(a.startDate, a.endDate, now);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(assignmentRoute(a.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      employerLine(a),
                      style: TextStyle(
                        fontSize: 14.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      payLine(a.pay),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (dates != null)
                      Text(
                        dates,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        WorkPill(
                          assignmentStatusLabel(a, now),
                          tone: assignmentTone(a, now),
                        ),
                        if (a.status == AssignmentStatus.completed &&
                            a.verifiedExperience)
                          const WorkPill(
                            'Verified by Omelo',
                            tone: WorkTone.good,
                            icon: Icons.verified,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home card
// ---------------------------------------------------------------------------

/// Home: today's shift, a work offer or extra shifts — only when there is
/// work to show. Opens My work.
class WorkHomeCard extends ConsumerWidget {
  const WorkHomeCard({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenForWorkNotices(ref);
    final assignments = ref.watch(myAssignmentsProvider).valueOrNull;
    final shifts = ref.watch(myWorkProvider).valueOrNull;
    if ((assignments == null || assignments.isEmpty) &&
        (shifts == null || shifts.isEmpty)) {
      return const SizedBox.shrink();
    }
    final now = workNow(ref);
    final overview = workOverview(shifts ?? const [], now);
    final offers = (assignments ?? const [])
        .where((a) => a.isOfferOpenAt(now))
        .toList();
    final ongoing = (assignments ?? const []).any((a) => a.status.isOngoing);
    if (overview.isEmpty && offers.isEmpty && !ongoing) {
      return const SizedBox.shrink();
    }

    final String title;
    final String body;
    final today = overview.today.where((s) => !s.isCancelled).toList();
    if (today.isNotEmpty) {
      final s = today.first;
      final st = checkInState(s, now);
      title =
          'Today: ${shiftTimeRange(s.startsAt, s.endsAt, s.timezone)}';
      body = [
        '${s.title} · ${shiftEmployerLine(s)}',
        if (st.canCheckIn) 'Check-in is open',
        if (st.canCheckOut) 'You are checked in',
      ].join(' · ');
    } else if (offers.isNotEmpty) {
      title = offers.length == 1
          ? '${offers.single.employerName} offered you work'
          : '${offers.length} work offers are waiting';
      body = offers.length == 1
          ? '${offers.single.title} · see the details and answer.'
          : 'See the details and answer.';
    } else if (overview.offers.isNotEmpty) {
      title = overview.offers.length == 1
          ? '1 extra shift offered'
          : '${overview.offers.length} extra shifts offered';
      body = 'Accept or decline them in My work.';
    } else if (overview.upcoming.isNotEmpty) {
      final s = overview.upcoming.first;
      title = 'Next shift: ${shiftDayLabel(s.startsAt, s.timezone, now)}';
      body =
          '${shiftTimeRange(s.startsAt, s.endsAt, s.timezone)} · ${s.title}';
    } else {
      title = 'My work';
      body = 'Your shifts, timesheets, pay and time off.';
    }
    final waiting = offers.length + overview.offers.length;
    final scheme = Theme.of(context).colorScheme;
    final icon = Icon(
      Icons.work_outline,
      size: 30,
      color: scheme.onPrimaryContainer,
    );
    return Padding(
      padding: padding,
      child: Material(
        color: scheme.primaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/work'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  waiting > 0
                      ? Badge(label: Text('$waiting'), child: icon)
                      : icon,
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          body,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Four big links to the rest of My work.
class WorkLinks extends StatelessWidget {
  const WorkLinks({super.key, this.pendingOffers = 0});
  final int pendingOffers;

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String label, String route, {int badge = 0}) =>
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          minTileHeight: 60,
          leading: Icon(icon, size: 26),
          title: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge > 0)
                Badge(
                  label: Text('$badge', semanticsLabel: '$badge waiting'),
                  largeSize: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () => context.push(route),
        );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          tile(
            Icons.assignment_ind_outlined,
            'My assignments',
            '/work/assignments',
            badge: pendingOffers,
          ),
          const Divider(height: 1),
          tile(Icons.schedule_outlined, 'Timesheets', '/work/timesheets'),
          const Divider(height: 1),
          tile(Icons.payments_outlined, 'Earnings', '/work/earnings'),
          const Divider(height: 1),
          tile(Icons.beach_access_outlined, 'Time off', '/work/leave'),
        ],
      ),
    );
  }
}
