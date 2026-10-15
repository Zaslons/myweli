import 'dart:async';

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
import '../../splash/open_animation_player.dart';
import '../../splash/splash_screen.dart';

/// Pro app-open screen: the MyWeli open animation, opening on « MyWeli Pro »,
/// over the light `#FAFAFA` the native pro splash ends on — then routing on.
/// Design: docs/design/pro-open-animation.md.
///
/// **The whole first pass, then the gate.** The animation plays through once —
/// wordmark → morph → spin (the mark erasing and redrawing) → the finished
/// mark — and rests on that mark ([OpenAnimationPlayer.rest]) before anything
/// may route (§2.2). The clock is the animation's own controller, never a
/// wall-clock timer beside it, so the gate cannot open on a mark the user has
/// not seen drawn.
///
/// **The session runs underneath.** The load is the one `ProAuthProvider`'s
/// constructor started before `runApp` (`auth.ready`) — the splash never starts
/// its own. Settled at the gate: the mark is already stopped on its end frame
/// and the screen routes. Still pending: the mark keeps spinning, and the
/// screen leaves at the end of a spin — always on the finished mark — once the
/// session is settled, or the stored session is read and [sessionDeadline] has
/// passed since the gate (§2.3).
///
/// **The composition is the timeline.** Every frame and duration is read from
/// the asset's markers (`intro`, `wordmark`, `loop`), so a designer's
/// replacement only has to keep the markers — `pro_open_animation_asset_test`
/// pins them.
class ProSplashScreen extends StatefulWidget {
  const ProSplashScreen({super.key});

  /// The Pro variant of the consumer `myweli_loader_mixed.json`.
  static const asset = 'assets/lottie/open/myweli_loader_mixed_pro.json';

  /// What a screen reader announces — the wordmark the animation draws.
  static const semanticsLabel = 'MyWeli Pro';

  /// How long the live membership refresh may hold the splash once the gate
  /// is open and the stored session is read. The refresh began before
  /// `runApp`, so by then it has had the whole first pass (5.68 s) and more;
  /// the version gate's bound, for the same reason — past it the network is
  /// the problem, and waiting only stalls the user (pro-open-animation.md
  /// §2.3). The screen still leaves only at a spin's end.
  // A network deadline, not motion — §9's tokens time movement; this times a
  // request, like `ClientVersionGate.deadline`.
  static const sessionDeadline = Duration(milliseconds: 1500); // ds-ignore

  /// Reduced motion's still during the intro (the full « MyWeli Pro »).
  static const wordmarkMarker = OpenAnimationPlayer.wordmarkMarker;

  /// The wordmark draws, holds and morphs into the mark.
  static const introMarker = OpenAnimationPlayer.introMarker;

  /// The spin — what repeats while the session is still loading.
  static const loopMarker = OpenAnimationPlayer.loopMarker;

  @override
  State<ProSplashScreen> createState() => _ProSplashScreenState();
}

class _ProSplashScreenState extends State<ProSplashScreen>
    with SingleTickerProviderStateMixin {
  late final OpenAnimationPlayer _player = OpenAnimationPlayer(vsync: this);

  /// Opens when the first pass and its rest are over — or at once if the
  /// asset could not load (never strand the user on a splash).
  final Completer<void> _gate = Completer<void>();
  Timer? _deadlineTimer;

  LottieComposition? _composition;

  /// The gate is open and the session is not: the screen is now waiting.
  bool _sessionPending = false;

  /// The asset failed and the still brand mark stands in for it.
  bool _assetFailed = false;

  /// A still on screen while the session loads says so (SYSTEM.md §9.1:
  /// a frozen logo and a broken screen look identical). With motion on, the
  /// spin is that signal.
  bool get _showCaption =>
      _sessionPending && (_player.reduceMotion || _assetFailed);

  @override
  void initState() {
    super.initState();
    // Starts nothing — it only awaits the constructor's load and the gate, so
    // there is no notify to keep out of this frame's build.
    _routeWhenReady();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Applied mid-pass too; the build that follows redraws the caption.
    _player.reduceMotion = reduceMotionOf(context);
  }

  Future<void> _routeWhenReady() async {
    final auth = Provider.of<ProAuthProvider>(context, listen: false);
    var settled = false;
    final ready = _quietly(auth.ready).whenComplete(() => settled = true);

    await _gate.future;
    if (!mounted) return;

    // Settled at the gate: the controller is stopped on the end frame — the
    // finished mark — and stays there. Nothing restarts; the screen goes.
    if (!settled) {
      setState(() => _sessionPending = true);
      final mayLeave = Completer<void>();
      void allow() {
        if (!mayLeave.isCompleted) mayLeave.complete();
      }

      unawaited(ready.then((_) => allow()));
      // The stored session first — local storage, so it is waited for:
      // without it there is no route to take. Then the live refresh, up to
      // the deadline, counted from the gate.
      unawaited(
        _quietly(auth.restored).then((_) {
          if (!mounted) return;
          _deadlineTimer = Timer(ProSplashScreen.sessionDeadline, allow);
        }),
      );

      final composition = _composition;
      final loop = composition?.getMarker(ProSplashScreen.loopMarker);
      if (composition == null || loop == null) {
        // No spin to end on — a broken asset, or a file without `loop` (its
        // end frame stays up): leave as soon as the session allows.
        await mayLeave.future;
      } else {
        // Spin until allowed; leave only at a spin's end, on the finished
        // mark. The first check always spins once: `allow` lands in a
        // microtask, after the gate already found the session pending.
        while (!mayLeave.isCompleted) {
          await _player.play(composition, from: loop.start);
          if (!mounted) return;
        }
      }
      _deadlineTimer?.cancel();
      if (!mounted) return;
    }

    // Past the deadline these answer from the stored session and the cached
    // membership; a later refresh reshapes the app in place, and a revoked
    // member is still routed by it — to « Invitations » or signed out
    // (docs/design/pro-rejoin-gate.md S9).
    if (auth.rejoinPending) {
      // Before the signed-in branch: the gate keeps the session live.
      context.go('/pro/invitations');
    } else if (auth.isAuthenticated) {
      context.go(auth.isStaff ? '/pro/staff' : '/pro/dashboard');
    } else {
      context.go('/pro/login');
    }
  }

  /// [future] without its error: a failure must still let the screen route.
  static Future<void> _quietly(Future<void> future) =>
      future.then<void>((_) {}, onError: (Object _) {});

  void _onLoaded(LottieComposition composition) {
    // Once: a rebuild never reloads an equal `AssetLottie`, but a second first
    // pass would silently lengthen the boot, so the guard is not left to that.
    if (_composition != null) return;
    _composition = composition;
    _player.play(composition).then((_) => _openGate());
  }

  void _openGate() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  void dispose() {
    _deadlineTimer?.cancel();
    _player.dispose();
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
                  controller: _player.controller,
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
    _openGate();
    if (mounted && !_assetFailed) setState(() => _assetFailed = true);
  }
}
