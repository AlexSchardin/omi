import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';

import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/platform/platform_manager.dart';

/// "Setting up your Omi": shown right after the guided voice introduction while the knowledge
/// graph is being prebuilt. Each line ticks off with a haptic, the last line holds until the real
/// work ([work]) finishes or [maxWait] passes, and a review ask appears early in the wait, when
/// the user has just invested in Omi and has nothing else to do.
class OnboardingConfiguringScreen extends StatefulWidget {
  final Future<void>? work;
  final VoidCallback onDone;
  final Duration stepDuration;
  final Duration maxWait;

  const OnboardingConfiguringScreen({
    super.key,
    required this.work,
    required this.onDone,
    this.stepDuration = const Duration(milliseconds: 1100),
    this.maxWait = const Duration(seconds: 12),
  });

  /// The line after which the review ask appears: after a few ticks have built momentum, well
  /// before the end so the remaining ticks keep running behind the dialog.
  static const int reviewAskAfterStep = 2;

  @override
  State<OnboardingConfiguringScreen> createState() => _OnboardingConfiguringScreenState();
}

class _OnboardingConfiguringScreenState extends State<OnboardingConfiguringScreen> {
  int _completed = 0;
  bool _reviewAsked = false;
  bool _finished = false;
  Timer? _timer;

  List<String> _steps(BuildContext context) => [
        context.l10n.onboardingConfiguringStepVoice,
        context.l10n.onboardingConfiguringStepLanguage,
        context.l10n.onboardingConfiguringStepMemories,
        context.l10n.onboardingConfiguringStepGraph,
        context.l10n.onboardingConfiguringStepSummaries,
        context.l10n.onboardingConfiguringStepReminders,
        context.l10n.onboardingConfiguringStepPersonalize,
      ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.stepDuration, (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final total = _steps(context).length;
    // The last line only completes once the real work is done.
    if (_completed >= total - 1) {
      _timer?.cancel();
      _finishLastStep();
      return;
    }
    setState(() => _completed++);
    OmiHaptics.light();
    if (_completed == OnboardingConfiguringScreen.reviewAskAfterStep && !_reviewAsked) {
      _reviewAsked = true;
      _askForReview();
    }
  }

  Future<void> _finishLastStep() async {
    try {
      await (widget.work ?? Future<void>.value()).timeout(widget.maxWait);
    } catch (_) {
      // A slow or failed prebuild must never strand onboarding; the graph step handles its own state.
    }
    if (!mounted || _finished) return;
    _finished = true;
    setState(() => _completed = _steps(context).length);
    await OmiHaptics.success();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) widget.onDone();
  }

  Future<void> _askForReview() async {
    PlatformManager.instance.analytics.onboardingStepCompleted('Configuring Review Ask Shown');
    final wantsToRate = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(context.l10n.onboardingConfiguringReviewTitle),
        content: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(context.l10n.onboardingConfiguringReviewBody),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.onboardingConfiguringReviewYes),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.onboardingConfiguringReviewNo),
          ),
        ],
      ),
    );
    PlatformManager.instance.analytics
        .onboardingStepCompleted(wantsToRate == true ? 'Configuring Review Yes' : 'Configuring Review No');
    if (wantsToRate == true && await InAppReview.instance.isAvailable()) {
      await InAppReview.instance.requestReview();
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: OmiColors.surface0,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(OmiSpacing.xl, OmiSpacing.xxl, OmiSpacing.xl, OmiSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(context.l10n.onboardingConfiguringTitle, style: OmiType.largeTitle),
                ),
                const SizedBox(height: OmiSpacing.xs),
                Text(
                  context.l10n.onboardingConfiguringSubtitle,
                  style: OmiType.body.copyWith(color: OmiColors.textSecondary),
                ),
                const SizedBox(height: OmiSpacing.xxl),
                for (var i = 0; i < steps.length; i++)
                  _StepRow(
                    label: steps[i],
                    state: i < _completed
                        ? _StepState.done
                        : i == _completed
                            ? _StepState.active
                            : _StepState.pending,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _StepState { pending, active, done }

class _StepRow extends StatelessWidget {
  final String label;
  final _StepState state;

  const _StepRow({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final Widget indicator = switch (state) {
      _StepState.done =>
        Icon(Icons.check_circle_rounded, color: OmiColors.accent, size: 28, key: const ValueKey('done')),
      _StepState.active => SizedBox(
          key: const ValueKey('active'),
          width: 28,
          height: 28,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: CircularProgressIndicator(strokeWidth: 2.5, color: OmiColors.accent),
          ),
        ),
      _StepState.pending => Icon(Icons.circle_outlined,
          color: OmiColors.textTertiary.withValues(alpha: 0.5), size: 28, key: const ValueKey('pending')),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: OmiMotion.quickDuration,
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: indicator,
          ),
          const SizedBox(width: OmiSpacing.md),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: OmiMotion.quickDuration,
              style: OmiType.headline.copyWith(
                color: state == _StepState.pending ? OmiColors.textTertiary : OmiColors.textPrimary,
                fontWeight: state == _StepState.active ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}
