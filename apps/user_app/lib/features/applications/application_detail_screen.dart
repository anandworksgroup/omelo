import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/account_repository.dart'
    show trustStatusProvider, isVerifyEmailToAcceptError;
import '../../data/applications_repository.dart';
import '../../data/messaging_repository.dart'
    show messagingRepositoryProvider, messagingError;
import 'applications_screen.dart';
import '../settings/account_widgets.dart' show showEmailVerificationSheet;
import '../representations/representation_widgets.dart'
    show SubmittedByLine;
import 'hiring_widgets.dart';

final applicationDetailProvider = FutureProvider.autoDispose
    .family<ApplicationDetail?, String>((ref, id) async {
  ref.watch(authStateProvider);
  return ref.watch(applicationsRepositoryProvider).detail(id);
});

/// `/applications/:id` — one application, end to end.
///
/// Notification deeplinks land here, so this screen must answer on its own:
/// where am I, what happened, what do I do now.
class ApplicationDetailScreen extends ConsumerStatefulWidget {
  const ApplicationDetailScreen({super.key, required this.applicationId});
  final String applicationId;

  @override
  ConsumerState<ApplicationDetailScreen> createState() =>
      _ApplicationDetailScreenState();
}

class _ApplicationDetailScreenState
    extends ConsumerState<ApplicationDetailScreen> {
  bool _busy = false;
  bool _openingChat = false;
  bool _justHired = false;
  final _viewedOffers = <String>{};

  ApplicationsRepository get _repo => ref.read(applicationsRepositoryProvider);

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(isSignedInProvider);
    final async = ref.watch(applicationDetailProvider(widget.applicationId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Application'),
        leading: context.canPop()
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'All applications',
                onPressed: () => context.go('/applications'),
              ),
      ),
      body: !signedIn
          ? _Message(
              text: 'Sign in to see this application.',
              button: 'Sign in',
              onPressed: () => context.push(
                  '/sign-in?next=/applications/${widget.applicationId}'),
            )
          : async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _Message(
                text: 'Could not load this application.',
                button: 'Try again',
                onPressed: _reload,
              ),
              data: (d) => d == null
                  ? _Message(
                      text: 'We could not find this application.',
                      button: 'See all applications',
                      onPressed: () => context.go('/applications'),
                    )
                  : AbsorbPointer(
                      absorbing: _busy,
                      child: RefreshIndicator(
                        onRefresh: () => ref.refresh(
                            applicationDetailProvider(widget.applicationId)
                                .future),
                        child: _body(context, d),
                      ),
                    ),
            ),
    );
  }

  Widget _body(BuildContext context, ApplicationDetail d) {
    final a = d.application;
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    final offer = a.latestOffer(now);
    if (offer != null) _markOfferViewed(offer, now);

    final interviews = [...a.interviews]..sort((x, y) {
        final ux = x.isUpcoming(now), uy = y.isUpcoming(now);
        if (ux != uy) return ux ? -1 : 1;
        final dx = x.scheduledAt ?? DateTime(0), dy = y.scheduledAt ?? DateTime(0);
        return ux ? dx.compareTo(dy) : dy.compareTo(dx);
      });

    final process = HiringProcess.steps(a,
        events: d.events, plannedRounds: d.plannedRounds, now: now);

    // The most recent completed round says "Final review" while the employer
    // decides.
    Interview? lastCompleted;
    for (final i in a.interviews.where((i) => i.isCompleted)) {
      if (lastCompleted == null ||
          (i.scheduledAt ?? DateTime(0))
              .isAfter(lastCompleted.scheduledAt ?? DateTime(0))) {
        lastCompleted = i;
      }
    }
    final inFinalReview = a.state == 'interview' &&
        lastCompleted != null &&
        a.nextInterview(now) == null;

    final timeline = d.events
        .map((e) => HiringCopy.event(e, a.companyName))
        .whereType<TimelineEntry>()
        .toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        ContentWidth.reading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(a.jobTitle,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: StatusChip(state: a.state),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(a.companyName.isEmpty ? 'Employer' : a.companyName,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant)),
              SubmittedByLine(applicationId: a.id),
              const SizedBox(height: 6),
              Text(
                [
                  if (a.payMin != null || a.payMax != null)
                    Fmt.pay(
                        min: a.payMin,
                        max: a.payMax,
                        currency: a.payCurrency,
                        period: a.payPeriod),
                  if (a.locationText != null) a.locationText!,
                  if (a.matchScore != null) '${a.matchScore}% match',
                ].join(' · '),
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.push('/job/${a.jobId}'),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('View job'),
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero, minimumSize: const Size(0, 44)),
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _openingChat ? null : () => _messageEmployer(a),
                icon: _openingChat
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.chat_bubble_outline),
                label: const Text('Message employer'),
              ),
              const SizedBox(height: 14),

              if (_justHired || a.isHired)
                _HiredBanner(celebrate: _justHired)
              else
                NextStepLine(step: HiringCopy.nextStep(a, now), large: true),

              if (a.state == 'rejected') ...[
                const SizedBox(height: 10),
                Text('This is one job, not a verdict.',
                    style: TextStyle(
                        fontSize: 13.5, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => context.go('/discover'),
                  child: const Text('Find similar work'),
                ),
              ],

              const SizedBox(height: 28),
              const SectionHeading('Hiring process'),
              const SizedBox(height: 12),
              ProcessStepper(steps: process),

              if (offer != null) ...[
                const SizedBox(height: 28),
                const SectionHeading('Your offer'),
                const SizedBox(height: 10),
                _OfferCard(
                  offer: offer,
                  now: now,
                  companyName: a.companyOrEmployer,
                  mustVerifyEmail: ref
                          .watch(trustStatusProvider)
                          .value
                          ?.mustVerifyEmailToAcceptOffer ??
                      false,
                  onAccept: () => _accept(offer, a),
                  onDecline: () => _decline(offer),
                ),
              ],

              if (interviews.isNotEmpty) ...[
                const SizedBox(height: 28),
                SectionHeading(
                    interviews.length == 1 ? 'Interview' : 'Interviews'),
                const SizedBox(height: 10),
                for (final i in interviews) ...[
                  _InterviewCard(
                    interview: i,
                    showFinalReview:
                        inFinalReview && identical(i, lastCompleted),
                    onConfirm: () => _confirm(i),
                    onCantAttend: () => _cantAttend(i),
                    onJoin: i.room == null ? null : () => _join(i.room!),
                  ),
                  const SizedBox(height: 12),
                ],
              ],

              const SizedBox(height: 28),
              const SectionHeading('What happened so far'),
              const SizedBox(height: 12),
              if (timeline.isEmpty)
                _TimelineTile(
                  entry: TimelineEntry('You applied', at: a.appliedAt),
                  last: true,
                )
              else
                for (var i = timeline.length - 1; i >= 0; i--)
                  _TimelineTile(entry: timeline[i], last: i == 0),

              if (a.isOpen) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => _withdraw(a),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant),
                  child: const Text('Withdraw application'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // -- Actions ---------------------------------------------------------------

  void _markOfferViewed(Offer offer, DateTime now) {
    if (!offer.isOpen(now) || _viewedOffers.contains(offer.id)) return;
    _viewedOffers.add(offer.id);
    // Fire and forget: seeing the offer must not depend on this succeeding.
    _repo.viewOffer(offer.id).catchError((_) {});
  }

  void _reload() {
    ref.invalidate(applicationDetailProvider(widget.applicationId));
    ref.invalidate(myApplicationsProvider);
  }

  Future<bool> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return true;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(done)));
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(HiringActionError.message(e))));
      return false;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reload();
      }
    }
  }

  /// Opens (or starts) the conversation about this application.
  Future<void> _messageEmployer(ApplicationSummary a) async {
    setState(() => _openingChat = true);
    try {
      final id = await ref.read(messagingRepositoryProvider).start(a.id);
      if (!mounted) return;
      await context.push('/messages/$id');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(messagingError(e))));
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  Future<void> _join(InterviewRoom room) async {
    await context.push('/meet/${room.roomName}');
    if (mounted) _reload();
  }

  Future<void> _confirm(Interview i) async {
    await _run(() => _repo.confirmInterview(i.id),
        'Thanks. The employer knows you will come.');
  }

  Future<void> _cantAttend(Interview i) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReasonSheet(
        title: "Can't attend?",
        body: 'Tell the employer why. They may offer another time.',
        choices: [
          'I am not well',
          'I have a clash with work',
          'I cannot travel there',
          'I found another job',
        ],
        minLength: 3,
        submit: 'Send',
      ),
    );
    if (reason == null) return;
    await _run(() => _repo.cancelInterview(i.id, reason),
        'The employer has been told you cannot attend.');
  }

  /// Opens the email check. True once the email is verified.
  Future<bool> _verifyEmail() async {
    final trust = ref.read(trustStatusProvider).value;
    final ok = await showEmailVerificationSheet(
        context, trust?.email ?? ref.read(currentUserProvider)?.email);
    ref.invalidate(trustStatusProvider);
    return ok;
  }

  Future<void> _accept(Offer offer, ApplicationSummary a) async {
    // The server may require a verified email before accepting (flag
    // email_required_to_accept_offer). Check first rather than fail.
    if (ref.read(trustStatusProvider).value?.mustVerifyEmailToAcceptOffer ==
        true) {
      if (!await _verifyEmail() || !mounted) return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept this offer?'),
        content: Text(
          'You are saying yes to ${offer.title ?? a.jobTitle} at '
          '${a.companyOrEmployer}'
          '${offer.startDate == null ? '' : ', starting ${HiringCopy.day(offer.startDate!)}'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, accept'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    var done = false;
    setState(() => _busy = true);
    try {
      await _repo.respondToOffer(offer.id, accept: true);
      done = true;
    } catch (e) {
      if (!mounted) return;
      if (isVerifyEmailToAcceptError(e)) {
        // Turned on since the page loaded: verify, then try once more.
        setState(() => _busy = false);
        if (await _verifyEmail() && mounted) {
          setState(() => _busy = true);
          try {
            await _repo.respondToOffer(offer.id, accept: true);
            done = true;
          } catch (e2) {
            if (mounted) _snack(HiringActionError.message(e2));
          }
        }
      } else {
        _snack(HiringActionError.message(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reload();
      }
    }
    if (done && mounted) {
      _snack("You're hired!");
      setState(() => _justHired = true);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> _decline(Offer offer) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReasonSheet(
        title: 'Decline this offer?',
        body: 'You can say why. This is optional and helps the employer.',
        choices: [
          'Pay is too low',
          'Too far from home',
          'I took another job',
          'The hours do not suit me',
        ],
        minLength: 0,
        submit: 'Decline offer',
        destructive: true,
      ),
    );
    if (reason == null) return;
    await _run(
        () => _repo.respondToOffer(offer.id, accept: false, reason: reason),
        'You declined the offer.');
  }

  Future<void> _withdraw(ApplicationSummary a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw application?'),
        content: Text(
          'You are telling ${a.companyOrEmployer} you no longer want '
          '${a.jobTitle}. Any interview will be cancelled. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _repo.withdraw(a.id), 'Application withdrawn.');
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _HiredBanner extends StatelessWidget {
  const _HiredBanner({required this.celebrate});
  final bool celebrate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: OmeloTheme.verified.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OmeloTheme.verified.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(celebrate ? Icons.celebration : Icons.verified,
              color: OmeloTheme.verified, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "You're hired!",
                  style: TextStyle(
                      fontSize: celebrate ? 20 : 17,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'This job is now on your verified work history.',
                  style: TextStyle(fontSize: 14.5, height: 1.4),
                ),
                const SizedBox(height: 6),
                const OmeloPill('Verified by Omelo',
                    icon: Icons.verified,
                    color: OmeloTheme.verified,
                    background: Color(0x1412805C)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InterviewCard extends StatefulWidget {
  const _InterviewCard({
    required this.interview,
    required this.showFinalReview,
    required this.onConfirm,
    required this.onCantAttend,
    required this.onJoin,
  });

  final Interview interview;
  final bool showFinalReview;
  final VoidCallback onConfirm;
  final VoidCallback onCantAttend;

  /// Null when the room could not be read.
  final VoidCallback? onJoin;

  @override
  State<_InterviewCard> createState() => _InterviewCardState();
}

class _InterviewCardState extends State<_InterviewCard> {
  Timer? _tick;

  bool get _live => widget.interview.isOmeloMeet && widget.interview.isOpen;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _InterviewCard old) {
    super.didUpdateWidget(old);
    _syncTimer();
  }

  void _syncTimer() {
    if (_live && _tick == null) {
      // The countdown ticks and the Join button turns on by itself.
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_live) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.interview;
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    final upcoming = i.isUpcoming(now);
    final when = i.scheduledAt;

    final (String statusText, Color statusColor) = switch (i.status) {
      'cancelled' => ('Cancelled', scheme.onSurfaceVariant),
      'completed' => ('Done', OmeloTheme.verified),
      'no_show_candidate' => ('Missed', OmeloTheme.danger),
      'no_show_employer' => ('Employer did not come', scheme.onSurfaceVariant),
      _ when !upcoming => ('Waiting for result', scheme.onSurfaceVariant),
      _ when i.isConfirmed => ('You confirmed', OmeloTheme.verified),
      _ => ('Please confirm', OmeloTheme.warning),
    };

    final format = i.meetingMode == null
        ? HiringCopy.interviewType(i.type)
        : MeetCopy.meetingMode(i.meetingMode, locationText: i.locationText);
    final formatIcon = switch (i.meetingMode) {
      'omelo_meet' => Icons.videocam_outlined,
      'phone' => Icons.phone_outlined,
      'in_person' => Icons.place_outlined,
      _ => Icons.work_outline,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    i.roundName ??
                        '${HiringCopy.interviewType(i.type)}'
                            '${(i.round ?? 1) > 1 ? ' · Round ${i.round}' : ''}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                OmeloPill(statusText,
                    color: statusColor,
                    background: statusColor.withValues(alpha: 0.10)),
              ],
            ),
            const SizedBox(height: 10),
            if (when != null)
              _Line(
                Icons.event,
                HiringCopy.dayTime(when),
                sub: [
                  if (i.durationMinutes != null)
                    'About ${i.durationMinutes} minutes',
                  'Your local time',
                ].join(' · '),
              ),
            _Line(
              formatIcon,
              format,
              copyable: i.meetingMode == 'in_person' && i.locationText != null,
              copyText: i.locationText,
            ),
            if (i.meetingMode != 'in_person' &&
                i.meetingMode != 'omelo_meet' &&
                i.locationText != null)
              _Line(Icons.place_outlined, i.locationText!, copyable: true),
            if (i.meetingUrl != null && !i.isOmeloMeet)
              _Line(Icons.videocam_outlined, i.meetingUrl!,
                  copyable: true, sub: 'Copy this link and open it at the time'),
            if (i.instructions != null)
              _Line(Icons.info_outline, i.instructions!),
            if (i.status == 'cancelled' && i.cancelReason != null)
              _Line(Icons.notes, 'Reason: ${i.cancelReason}'),
            if (i.isCompleted) ...[
              const SizedBox(height: 4),
              _CompletedNote(showFinalReview: widget.showFinalReview),
            ],
            if (_live) ...[
              const SizedBox(height: 4),
              _MeetJoin(interview: i, now: now, onJoin: widget.onJoin),
            ],
            if (upcoming) ...[
              const SizedBox(height: 8),
              if (!i.isConfirmed) ...[
                SizedBox(
                  width: double.infinity,
                  // With a Join button above, confirming is the secondary action.
                  child: _live
                      ? OutlinedButton(
                          onPressed: widget.onConfirm,
                          child: const Text("Confirm I'll attend"),
                        )
                      : FilledButton(
                          onPressed: widget.onConfirm,
                          child: const Text("Confirm I'll attend"),
                        ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: widget.onCantAttend,
                  child: const Text("I can't attend"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Countdown and the Join Interview button for an Omelo Meet round.
class _MeetJoin extends StatelessWidget {
  const _MeetJoin({
    required this.interview,
    required this.now,
    required this.onJoin,
  });

  final Interview interview;
  final DateTime now;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final i = interview;
    final scheme = Theme.of(context).colorScheme;
    final state = i.meetWindow.state(now, roomStatus: i.room?.status);
    if (state == MeetWindowState.closed) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('This interview room is closed.',
            style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant)),
      );
    }

    final open = state == MeetWindowState.open;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (i.scheduledAt != null)
            Text(
              meetStartsInLabel(i.scheduledAt!, now),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          const SizedBox(height: 4),
          Text(
            open
                ? 'The waiting room is open.'
                : 'You can join 15 minutes before it starts.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14.5),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: open ? onJoin : null,
            icon: const Icon(Icons.videocam),
            label: const Text('Join Interview'),
          ),
          if (open && onJoin == null) ...[
            const SizedBox(height: 6),
            const Text('Pull down to refresh if the button stays grey.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 8),
          Text(
            'Opens inside Omelo. No other app needed. ${MeetCopy.notRecorded}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CompletedNote extends StatelessWidget {
  const _CompletedNote({required this.showFinalReview});
  final bool showFinalReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OmeloTheme.verified.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: OmeloTheme.verified, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Interview completed ✓ — submitted to the employer.'
              '${showFinalReview ? ' ${MeetCopy.finalReview}.' : ''}',
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.now,
    required this.companyName,
    required this.onAccept,
    required this.onDecline,
    this.mustVerifyEmail = false,
  });

  final Offer offer;
  final DateTime now;
  final String companyName;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  /// The server wants a verified email before this offer can be accepted;
  /// [onAccept] then opens the email check first.
  final bool mustVerifyEmail;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    final scheme = Theme.of(context).colorScheme;
    final open = o.isOpen(now);

    final (String? statusText, Color statusColor) = switch (o.status) {
      'accepted' => ('Accepted', OmeloTheme.verified),
      'declined' => ('You declined', scheme.onSurfaceVariant),
      'withdrawn' => ('Withdrawn by employer', scheme.onSurfaceVariant),
      _ when o.isExpired(now) => ('Expired', scheme.onSurfaceVariant),
      _ => (null, scheme.primary),
    };

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: open ? OmeloTheme.verified : scheme.outlineVariant,
            width: open ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(o.title ?? 'Job offer',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                if (statusText != null)
                  OmeloPill(statusText,
                      color: statusColor,
                      background: statusColor.withValues(alpha: 0.10)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              Fmt.pay(
                  min: o.payAmount,
                  currency: o.payCurrency,
                  period: o.payPeriod),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (o.startDate != null)
              _Line(Icons.play_circle_outline,
                  'Starts ${HiringCopy.date(o.startDate!)}'),
            if (o.expiresAt != null && open)
              _Line(Icons.hourglass_bottom,
                  'Answer by ${HiringCopy.dayTime(o.expiresAt!)}'),
            if (o.conditions != null)
              _Line(Icons.rule, o.conditions!, sub: 'Conditions'),
            if (o.benefits.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final b in o.benefits)
                    OmeloPill(Fmt.benefit(b),
                        icon: Icons.check,
                        color: OmeloTheme.verified,
                        background: const Color(0x1412805C)),
                ],
              ),
            ],
            if (open) ...[
              const SizedBox(height: 16),
              ResponsiveFieldRow(
                spacing: 8,
                children: [
                  mustVerifyEmail
                      ? FilledButton.icon(
                          onPressed: onAccept,
                          icon: const Icon(Icons.mark_email_read_outlined),
                          label: const Text('Verify your email to accept'),
                        )
                      : FilledButton(
                          onPressed: onAccept,
                          child: const Text('Accept offer'),
                        ),
                  OutlinedButton(
                    onPressed: onDecline,
                    child: const Text('Decline'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Never pay money to accept a job. $companyName should not ask '
                'for fees or your original documents.',
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text,
      {this.sub, this.copyable = false, this.copyText});
  final IconData icon;
  final String text;
  final String? sub;
  final bool copyable;
  final String? copyText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 19, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(text,
                    style: const TextStyle(fontSize: 15, height: 1.4)),
                if (sub != null)
                  Text(sub!,
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copyText ?? text));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied')));
              },
            ),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.entry, required this.last});
  final TimelineEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = toneColor(context, entry.tone);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                const SizedBox(height: 3),
                Container(
                  width: 12,
                  height: 12,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: scheme.outlineVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  if (entry.detail != null)
                    Text(entry.detail!,
                        style: const TextStyle(fontSize: 14, height: 1.35)),
                  if (entry.at != null)
                    Text(HiringCopy.dayTime(entry.at!),
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet asking for a reason, with quick picks for low typing.
class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet({
    required this.title,
    required this.body,
    required this.choices,
    required this.minLength,
    required this.submit,
    this.destructive = false,
  });

  final String title;
  final String body;
  final List<String> choices;
  final int minLength;
  final String submit;
  final bool destructive;

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _controller.text.trim().length >= widget.minLength;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ContentWidth.reading(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(widget.body, style: const TextStyle(fontSize: 14.5)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in widget.choices)
                      ChoiceChip(
                        label: Text(c),
                        selected: _controller.text == c,
                        onSelected: (_) => setState(() => _controller.text = c),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  maxLines: 3,
                  minLines: 1,
                  maxLength: 300,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: widget.minLength > 0
                        ? 'Write a short reason'
                        : 'Reason (optional)',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: widget.destructive
                      ? FilledButton.styleFrom(
                          backgroundColor: OmeloTheme.danger)
                      : null,
                  onPressed: valid
                      ? () => Navigator.pop(context, _controller.text.trim())
                      : null,
                  child: Text(widget.submit),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    required this.button,
    required this.onPressed,
  });
  final String text;
  final String button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              FilledButton(onPressed: onPressed, child: Text(button)),
            ],
          ),
        ),
      );
}
