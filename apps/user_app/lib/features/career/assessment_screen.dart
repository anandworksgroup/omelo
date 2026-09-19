import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/career_repository.dart';
import '../work/work_widgets.dart'
    show RepresentationMessage, WorkNote, WorkTone, workBackButton;
import 'career_widgets.dart';

/// `/career/assessment/<skill>` — a short Omelo test for one skill.
///
/// One question per page with a countdown to the attempt's end. The server
/// grades it; the result says which questions were right without showing
/// the right answers, and a pass adds "Passed Omelo test" evidence to the
/// skill (so readiness rises when the path reloads).
class AssessmentScreen extends ConsumerStatefulWidget {
  const AssessmentScreen({
    super.key,
    required this.skillId,
    this.skillName,
    this.identityId,
  });

  final String skillId;
  final String? skillName;
  final String? identityId;

  @override
  ConsumerState<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends ConsumerState<AssessmentScreen> {
  AssessmentSession? _session;
  Object? _startError;
  bool _starting = true;

  final _chosen = <String, int>{};
  int _page = 0;

  Timer? _ticker;
  Duration? _left;

  bool _submitting = false;
  String? _submitError;
  AssessmentResult? _result;

  @override
  void initState() {
    super.initState();
    _start(first: true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime _now() => ref.read(careerClockProvider)();

  Future<void> _start({bool first = false}) async {
    void reset() {
      _starting = true;
      _startError = null;
      _session = null;
      _result = null;
      _submitError = null;
      _left = null;
      _chosen.clear();
      _page = 0;
    }

    // setState is not allowed before the first build.
    first ? reset() : setState(reset);
    try {
      final s = await ref
          .read(careerRepositoryProvider)
          .startAssessment(widget.skillId, identityId: widget.identityId);
      if (!mounted) return;
      if (s == null || s.questions.isEmpty) {
        setState(() => _startError = 'This test is not ready yet.');
        return;
      }
      setState(() => _session = s);
      _tick();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } catch (e) {
      if (mounted) setState(() => _startError = e);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _tick() {
    final s = _session;
    if (!mounted || s == null) return;
    final left = s.remaining(_now());
    setState(() => _left = left);
    if (left != null && left == Duration.zero) _ticker?.cancel();
  }

  bool get _timeUp => _left == Duration.zero;

  Future<void> _submit() async {
    final s = _session;
    if (s == null) return;
    final answers = answersInOrder(s.questions, _chosen);
    if (answers == null) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final r = await ref
          .read(careerRepositoryProvider)
          .submitAssessment(s.attemptId, answers);
      if (!mounted) return;
      _ticker?.cancel();
      invalidateCareer(ref);
      setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _submitError = careerError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _backToPath() {
    if (context.canPop()) {
      context.pop(_result != null);
    } else {
      context.go('/career');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _session?.title ??
        (widget.skillName == null ? 'Skill test' : '${widget.skillName} test');
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: workBackButton(context, '/career'),
        actions: [
          if (_session != null && _result == null && _left != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: _Countdown(left: _left!)),
            ),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_starting) return const Center(child: CircularProgressIndicator());
    if (_startError != null) {
      final e = _startError!;
      return RepresentationMessage(
        icon: Icons.hourglass_bottom,
        title: 'You cannot take this test right now',
        body: e is String ? e : careerError(e),
        actionLabel: 'Back to my career path',
        onAction: _backToPath,
      );
    }
    final r = _result;
    if (r != null) return _ResultView(result: r, session: _session!, onDone: _backToPath);
    return _questions(context, _session!);
  }

  Widget _questions(BuildContext context, AssessmentSession s) {
    final scheme = Theme.of(context).colorScheme;
    final gutter = Breakpoints.of(context).gutter;
    final q = s.questions[_page];
    final last = _page == s.questions.length - 1;
    final answered = s.questions.where((x) => _chosen.containsKey(x.id)).length;
    final all = answered == s.questions.length;

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 32),
      children: [
        ContentWidth.reading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Question ${_page + 1} of ${s.questions.length}',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              // Jump to any question; answered ones are filled.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < s.questions.length; i++)
                    ChoiceChip(
                      label: Text('${i + 1}'),
                      selected: i == _page,
                      avatar: _chosen.containsKey(s.questions[i].id)
                          ? const Icon(Icons.check, size: 16)
                          : null,
                      onSelected: (_) => setState(() => _page = i),
                      tooltip: 'Question ${i + 1}',
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                q.prompt,
                style: const TextStyle(fontSize: 18, height: 1.4, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < q.options.length; i++)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: RadioListTile<int>(
                    value: i,
                    groupValue: _chosen[q.id],
                    onChanged: _timeUp
                        ? null
                        : (v) {
                            if (v != null) setState(() => _chosen[q.id] = v);
                          },
                    title: Text(q.options[i], style: const TextStyle(fontSize: 15.5)),
                  ),
                ),
              if (_timeUp) ...[
                const SizedBox(height: 8),
                const WorkNote(
                  'Time is up for this attempt. Start again to get a new set '
                  'of questions.',
                  tone: WorkTone.warning,
                  icon: Icons.timer_off_outlined,
                ),
                const SizedBox(height: 10),
                FilledButton(onPressed: () => _start(), child: const Text('Start again')),
              ] else ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (_page > 0)
                      OutlinedButton(
                        onPressed: () => setState(() => _page--),
                        child: const Text('Back'),
                      ),
                    const Spacer(),
                    if (!last)
                      FilledButton(
                        onPressed: () => setState(() => _page++),
                        child: const Text('Next'),
                      )
                    else
                      FilledButton(
                        onPressed: !all || _submitting ? null : _submit,
                        child: Text(_submitting ? 'Checking…' : 'Submit answers'),
                      ),
                  ],
                ),
                if (last && !all) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Answer every question to submit ($answered of '
                    '${s.questions.length} answered).',
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
              if (_submitError != null) ...[
                const SizedBox(height: 10),
                WorkNote(_submitError!, tone: WorkTone.warning),
              ],
              if (s.passPercent != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Pass mark: ${s.passPercent}%. Your answers are checked by '
                  'Omelo; employers see only that you passed.',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.left});
  final Duration left;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final low = left.inSeconds < 60;
    final color = low ? OmeloTheme.danger : scheme.onSurfaceVariant;
    return Semantics(
      label: 'Time left ${countdownLabel(left)}',
      child: ExcludeSemantics(
        child: OmeloPill(
          countdownLabel(left),
          icon: Icons.timer_outlined,
          color: color,
          background: low ? OmeloTheme.danger.withValues(alpha: 0.12) : null,
        ),
      ),
    );
  }
}

class _ResultView extends ConsumerWidget {
  const _ResultView({
    required this.result,
    required this.session,
    required this.onDone,
  });

  final AssessmentResult result;
  final AssessmentSession session;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = result;
    final scheme = Theme.of(context).colorScheme;
    final gutter = Breakpoints.of(context).gutter;
    final now = ref.watch(careerClockProvider)();
    final color = r.passed ? OmeloTheme.verified : OmeloTheme.warning;
    final prompts = {for (final q in session.questions) q.id: q.prompt};
    final retry = r.retryLine(now);

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 24, gutter, 32),
      children: [
        ContentWidth.reading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                r.passed ? Icons.emoji_events_outlined : Icons.refresh,
                size: 56,
                color: color,
              ),
              const SizedBox(height: 10),
              Text(
                r.passed ? 'You passed' : 'Not passed this time',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color),
              ),
              const SizedBox(height: 6),
              Text(
                'You scored ${r.scorePercent}% (${r.correct} of ${r.total} correct).'
                '${r.passPercent == null ? '' : ' The pass mark is ${r.passPercent}%.'}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              if (r.passed)
                const WorkNote(
                  '"Passed Omelo test" is now evidence on this skill. Your '
                  'readiness updates when you go back.',
                  tone: WorkTone.good,
                  icon: Icons.verified,
                )
              else
                WorkNote(
                  [
                    'Look at the questions you missed, practise, and try again.',
                    ?retry,
                  ].join(' '),
                  tone: WorkTone.warning,
                  icon: Icons.schedule,
                ),
              const SizedBox(height: 18),
              const Text(
                'Your answers',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < r.review.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          r.review[i].correct ? Icons.check_circle : Icons.cancel_outlined,
                          color: r.review[i].correct ? OmeloTheme.verified : OmeloTheme.danger,
                        ),
                        title: Text(
                          'Question ${i + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          prompts[r.review[i].questionId] ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          r.review[i].correct ? 'Correct' : 'Not correct',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: r.review[i].correct ? OmeloTheme.verified : scheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onDone,
                child: const Text('Back to my career path'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
