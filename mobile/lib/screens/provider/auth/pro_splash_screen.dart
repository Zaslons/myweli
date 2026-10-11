import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../../../core/a11y/reduce_motion.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../splash/splash_screen.dart';

/// Pro app-open screen: the MyWeli open animation, opening on « MyWeli Pro »,
/// over the light `#FAFAFA` the native pro splash ends on — then routing on.
/// Design: docs/design/pro-open-animation.md.
///
/// **Two gates, run side by side.** The session load starts after the first
/// frame and the intro plays at the same time; the screen routes when BOTH are
/// done — never after a fixed delay chained in front of the load (the old
/// 2 s `Future.delayed` → `loadCurrentProvider()`).
///
/// **The composition is the timeline.** Every frame and duration below is read
/// from the asset's markers (`intro`, `wordmark`, `loop`), so a designer's
/// replacement only has to keep the markers — `pro_open_animation_asset_test`
/// pins them.
class ProSplashScreen extends StatefulWidget {
  const ProSplashScreen({super.key});

  /// The Pro variant of the consumer `myweli_loader_mixed.json`.
  static const asset = 'assets/lottie/open/myweli_loader_mixed_pro.json';

  /// What a screen reader announces — the wordmark the animation draws.
  static const semanticsLabel = 'MyWeli Pro';

  /// The still frame reduced motion holds (the full « MyWeli Pro »).
  static const wordmarkMarker = 'wordmark';

  /// Plays once: wordmark → morph into the mark.
  static const introMarker = 'intro';

  /// Repeats while the session is still loading: the mark redraw only.
  static const loopMarker = 'loop';

  @override
  State<ProSplashScreen> createState() => _ProSplashScreenState();
}

class _ProSplashScreenState extends State<ProSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  /// Completes when the intro has had its time — played (motion on), held
  /// still (reduced motion: the same boot, not a shorter one), or skipped
  /// because the asset could not load (never strand the user on a splash).
  final Completer<void> _intro = Completer<void>();
  Timer? _introTimer;

  LottieComposition? _composition;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: `loadCurrentProvider` notifies synchronously, and
    // a notify inside this frame's build would trip any listener's
    // markNeedsBuild. One frame late is still fully overlapped with the intro.
    WidgetsBinding.instance.addPostFrameCallback((_) => _routeWhenReady());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = reduceMotionOf(context);
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      _syncMotion();
    }
  }

  Future<void> _routeWhenReady() async {
    if (!mounted) return;
    final auth = Provider.of<ProAuthProvider>(context, listen: false);
    await Future.wait<void>([auth.loadCurrentProvider(), _intro.future]);
    if (!mounted) return;

    if (auth.isAuthenticated) {
      context.go(auth.isStaff ? '/pro/staff' : '/pro/dashboard');
    } else {
      context.go('/pro/login');
    }
  }

  void _onLoaded(LottieComposition composition) {
    _composition = composition;
    // Once: a rebuild never reloads an equal `AssetLottie`, but a restarted
    // timer would silently lengthen the boot, so the guard is not left to that.
    if (_introTimer == null) {
      final intro = composition.getMarker(ProSplashScreen.introMarker);
      _introTimer = Timer(
        _framesToDuration(composition, intro?.durationFrames),
        _onIntroDone,
      );
    }
    _syncMotion();
  }

  void _onIntroDone() {
    _finishIntro();
    _syncMotion();
  }

  void _finishIntro() {
    if (!_intro.isCompleted) _intro.complete();
  }

  /// Puts the controller where the current state says it should be.
  void _syncMotion() {
    final composition = _composition;
    if (composition == null) return;

    if (_reduceMotion) {
      _controller
        ..stop()
        ..value = _stillProgress(composition);
      return;
    }

    if (!_intro.isCompleted) {
      final end = composition.getMarker(ProSplashScreen.introMarker)?.end ?? 1;
      if (_controller.value >= end) return;
      _controller.animateTo(
        end,
        duration: _framesToDuration(
          composition,
          (end - _controller.value) * composition.durationFrames,
        ),
      );
      return;
    }

    // The intro is over and the session is still loading: redraw the mark,
    // never the wordmark. No `loop` marker → hold the intro's last frame.
    final loop = composition.getMarker(ProSplashScreen.loopMarker);
    if (loop == null) {
      _controller.stop();
      return;
    }
    _controller.repeat(
      min: loop.start,
      max: loop.end,
      period: _framesToDuration(composition, loop.durationFrames),
    );
  }

  /// Reduced motion's still: the middle of the `wordmark` hold, where every
  /// letter of « MyWeli Pro » is at full opacity. A file without the marker
  /// falls back to the end frame — the finished mark, as the consumer splash.
  static double _stillProgress(LottieComposition composition) {
    final wordmark = composition.getMarker(ProSplashScreen.wordmarkMarker);
    if (wordmark == null) return 1;
    return (wordmark.start + wordmark.end) / 2;
  }

  /// A span of composition frames as wall-clock time (null → the whole file).
  static Duration _framesToDuration(
    LottieComposition composition,
    double? frames,
  ) {
    final seconds =
        (frames ?? composition.durationFrames) / composition.frameRate;
    return Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round(),
    );
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Light — the native pro splash ends on #FAFAFA with the black mark, so
      // the hand-off is seamless (the consumer splash does the same).
      backgroundColor: AppColors.surface,
      body: Center(
        child: Semantics(
          label: ProSplashScreen.semanticsLabel,
          image: true,
          child: ExcludeSemantics(
            child: Lottie.asset(
              ProSplashScreen.asset,
              controller: _controller,
              onLoaded: _onLoaded,
              // The consumer splash's size: the same mark, at the same scale.
              width: SplashScreen.animationWidth,
              errorBuilder: (context, error, stackTrace) {
                // A bundled asset that fails to decode is a broken build — but
                // the session gate must still be the only thing left to wait
                // on, never a splash that cannot end.
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _finishIntro(),
                );
                return Text(
                  ProSplashScreen.semanticsLabel,
                  style: AppTextStyles.displaySmall.copyWith(
                    color: AppColors.textPrimary,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
