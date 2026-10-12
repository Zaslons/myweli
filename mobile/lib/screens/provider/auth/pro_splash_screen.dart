import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../../../core/a11y/reduce_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/brand_loader.dart';
import '../../splash/splash_screen.dart';

/// Pro app-open screen: the MyWeli open animation, opening on « MyWeli Pro »,
/// over the light `#FAFAFA` the native pro splash ends on — then routing on.
/// Design: docs/design/pro-open-animation.md.
///
/// **Two gates, run side by side.** The session load is the one
/// `ProAuthProvider`'s constructor started before `runApp` (`auth.ready`) —
/// the splash never starts its own — and the intro plays meanwhile; the
/// screen routes when BOTH are done, never after a fixed delay chained in
/// front of the load (the old 2 s `Future.delayed` → `loadCurrentProvider()`).
///
/// **A bounded wait.** Once the intro is over and the stored session is read,
/// the live membership refresh gets [sessionDeadline] more; past it the screen
/// routes on the stored session and the refresh finishes in the background.
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

  /// How long the live membership refresh may hold the splash once the intro
  /// is over and the stored session is read. The refresh began before
  /// `runApp`, so by then it has had the whole intro (2.96 s) and more; the
  /// version gate's bound, for the same reason — past it the network is the
  /// problem, and waiting only stalls the user (pro-open-animation.md §2.3).
  // A network deadline, not motion — §9's tokens time movement; this times a
  // request, like `ClientVersionGate.deadline`.
  static const sessionDeadline = Duration(milliseconds: 1500); // ds-ignore

  /// Reduced motion's still DURING the intro (the full « MyWeli Pro »); once
  /// the intro is over and the session is still loading it is the end frame.
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
  Timer? _deadlineTimer;

  LottieComposition? _composition;
  bool _reduceMotion = false;

  /// The intro is over and the session is not: the screen is now waiting.
  bool _sessionPending = false;

  /// The asset failed and the still brand mark stands in for it.
  bool _assetFailed = false;

  /// A still on screen while the session loads says so (SYSTEM.md §9.1:
  /// a frozen logo and a broken screen look identical). With motion on, the
  /// redraw loop is that signal.
  bool get _showCaption => _sessionPending && (_reduceMotion || _assetFailed);

  @override
  void initState() {
    super.initState();
    // Starts nothing — it only awaits the constructor's load and the intro, so
    // there is no notify to keep out of this frame's build.
    _routeWhenReady();
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
    final auth = Provider.of<ProAuthProvider>(context, listen: false);
    var settled = false;
    final ready = _quietly(auth.ready).whenComplete(() => settled = true);

    await _intro.future;
    if (!mounted) return;
    if (!settled) {
      setState(() => _sessionPending = true);
      // Only the still depends on it; the loop is already running, and a
      // second `repeat` would restart it a few frames off.
      if (_reduceMotion) _syncMotion();
    }

    // The stored session first — local storage, so it is waited for: without
    // it there is no route to take. Then the live refresh, up to the deadline.
    await _quietly(auth.restored);
    if (!mounted) return;
    final deadline = Completer<void>();
    _deadlineTimer = Timer(ProSplashScreen.sessionDeadline, deadline.complete);
    await Future.any<void>([ready, deadline.future]);
    _deadlineTimer?.cancel();
    if (!mounted) return;

    // Past the deadline these answer from the stored session and the cached
    // membership; a later refresh reshapes the app in place, and a revoked
    // member is still signed out by it (`_signOutRevoked`).
    if (auth.isAuthenticated) {
      context.go(auth.isStaff ? '/pro/staff' : '/pro/dashboard');
    } else {
      context.go('/pro/login');
    }
  }

  /// [future] without its error: a failure must still let the screen route.
  static Future<void> _quietly(Future<void> future) =>
      future.then<void>((_) {}, onError: (Object _) {});

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
        ..value = _stillProgress(composition, waiting: _sessionPending);
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
    // Clamped: lottie ends a composition at `op - 0.01`, so a marker running
    // to the last frame ends a hair past progress 1.0 — and `repeat` asserts
    // its bounds sit inside the controller's.
    final min = clampDouble(loop.start, 0, 1);
    final max = clampDouble(loop.end, 0, 1);
    _controller.repeat(
      min: min,
      max: max,
      period: _framesToDuration(
        composition,
        (max - min) * composition.durationFrames,
      ),
    );
  }

  /// Reduced motion's still. During the intro: the middle of the `wordmark`
  /// hold, where every letter of « MyWeli Pro » is at full opacity. Once the
  /// screen is [waiting] on the session: the end frame — the finished mark
  /// every pass of the redraw loop comes to rest on, so turning the flag on
  /// mid-loop never jumps back to the wordmark. A file without the marker
  /// holds the end frame throughout, as the consumer splash does.
  static double _stillProgress(
    LottieComposition composition, {
    required bool waiting,
  }) {
    final wordmark = composition.getMarker(ProSplashScreen.wordmarkMarker);
    if (waiting || wordmark == null) return 1;
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
    _deadlineTimer?.cancel();
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
        // A Stack sized by the mark alone, so the caption below never moves
        // the mark off the centre the native splash put it on.
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Semantics(
              label: ProSplashScreen.semanticsLabel,
              image: true,
              child: ExcludeSemantics(
                child: Lottie.asset(
                  ProSplashScreen.asset,
                  controller: _controller,
                  onLoaded: _onLoaded,
                  // The consumer splash's size: the same mark, at the same
                  // scale.
                  width: SplashScreen.animationWidth,
                  errorBuilder: (context, error, stackTrace) {
                    // A bundled asset that fails to decode is a broken build —
                    // but the session gate must still be the only thing left
                    // to wait on, never a splash that cannot end.
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _onAssetFailed(),
                    );
                    // The still brand mark, as `BrandLoader` holds it — the
                    // logo is never typed text (branding-integration.md §2).
                    return SvgPicture.asset(
                      'assets/brand/myweli_mark_black.svg',
                      height: AppTheme.iconXL,
                    );
                  },
                ),
              ),
            ),
            if (_showCaption)
              // Hung from the mark's bottom edge and dropped by its own
              // height: below the mark, outside the Stack's size.
              Positioned(
                bottom: 0,
                child: FractionalTranslation(
                  translation: const Offset(0, 1),
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppTheme.spacingS),
                    // A live region: it appears away from focus, after the
                    // intro, and is announced as it does (SYSTEM.md §15).
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      child: Text(
                        BrandLoader.semanticsLabel,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onAssetFailed() {
    _finishIntro();
    if (mounted && !_assetFailed) setState(() => _assetFailed = true);
  }
}
