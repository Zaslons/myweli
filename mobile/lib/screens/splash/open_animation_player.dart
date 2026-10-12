import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

/// The open animation's clock — both splash screens play their composition
/// through it. Design: docs/design/pro-open-animation.md §2.2 (the pass, the
/// gate, the clock), §2.4 (reduced motion), §2.8 (the consumer splash).
///
/// **A pass** plays the composition from a start frame to its END frame — the
/// finished mark — and then rests there for [rest]. [play] completes only
/// once the rest is over, so a screen that leaves on it always leaves on the
/// finished mark, held long enough to be seen (owner, Pro build 560: « on doit
/// voir au moins un tour du logo »).
///
/// **The clock is the ticker, not the wall.** With motion on, a pass is over
/// when the controller has DRAWN its end frame (`animateTo` completing on a
/// ticker frame), and the rest is counted from that frame. A wall-clock timer
/// started beside the animation — what the Pro screen used to run — keeps
/// going when frames do not: a slow first frame on a cold start, a janky
/// low-end Android, an app sent to the background mid-splash. It then routes
/// on a mark the user never saw drawn. The ticker cannot get ahead of what is
/// on screen, because it is what is on screen.
///
/// Under reduced motion nothing ticks (the picture is a still, SYSTEM.md
/// §9.1), so timers stand in for the frames — the first one started from the
/// frame that first SHOWS the still, never from the decode. The boot is the
/// same length either way: the still holds the frames motion would have played.
class OpenAnimationPlayer {
  OpenAnimationPlayer({required TickerProvider vsync})
    : controller = AnimationController(
        vsync: vsync,
        // This controller is the route gate's clock, so the framework's 5 %
        // scale under the OS flag must never reach it — §9.1: a content timer
        // must not be collapsed. Under that flag nothing animates anyway: the
        // stills below take over.
        animationBehavior: AnimationBehavior.preserve,
      );

  /// The hold where every letter of the wordmark is at full opacity — reduced
  /// motion's still during the intro.
  static const wordmarkMarker = 'wordmark';

  /// The wordmark draws, holds, and M/W morph into the mark. Under reduced
  /// motion it is held as the wordmark still; past it, as the finished mark.
  static const introMarker = 'intro';

  /// The spin: the mark erases and redraws, ending on the finished mark. Its
  /// start is where every later pass begins; it runs to the file's end frame.
  static const loopMarker = 'loop';

  /// How long the finished mark is held at the end of a pass before the
  /// screen may move on — both apps (pro-open-animation.md §2.2).
  // A content hold, not motion (SYSTEM.md §9): how long a still mark is LOOKED
  // AT, like the story reel's reading time. Nothing moves during it, so §9's
  // 50–400 ms ladder, which times movement, cannot name it.
  static const rest = Duration(milliseconds: 500); // ds-ignore

  /// Drives the Lottie. The screens hand it to `Lottie.asset(controller:)`.
  final AnimationController controller;

  LottieComposition? _composition;
  bool _reduceMotion = false;

  /// Bumped whenever something else takes over the controller (a new pass,
  /// the flag flipping, [dispose]). A hold timer, a post-frame start or a
  /// ticker future that is no longer the current driver stands down.
  int _driver = 0;

  /// Completes when the current [play] is over — end frame AND rest.
  Completer<void>? _done;

  /// Between a pass's start and its end frame: the flag acts only then.
  bool _playing = false;

  Timer? _holdTimer;
  Timer? _restTimer;
  bool _disposed = false;

  /// Whether passes are held still rather than played.
  bool get reduceMotion => _reduceMotion;

  /// Applies the OS flag — at once, mid-pass included.
  ///
  /// ON mid-pass: the picture freezes on the still for where the pass is, and
  /// the frames it had left are held, so the boot keeps its length. OFF
  /// mid-hold: the pass carries on as motion from the still on screen. During
  /// a rest the picture is the finished mark in both modes — nothing changes.
  set reduceMotion(bool value) {
    if (value == _reduceMotion) return;
    _reduceMotion = value;
    if (!_playing || _composition == null) return;
    if (value) {
      _hold(from: controller.value);
    } else {
      _animate(from: controller.value);
    }
  }

  /// Plays one pass, [from] (a progress: 0 for the whole file, the `loop`
  /// marker's start for a spin) to the end frame, then rests on the finished
  /// mark. Completes when the rest is over; never once [dispose]d.
  Future<void> play(LottieComposition composition, {double from = 0}) {
    assert(_done == null, 'one pass at a time');
    _composition = composition;
    final done = _done = Completer<void>();
    _playing = true;
    final start = clampDouble(from, 0, 1);

    if (!_reduceMotion) {
      // The ticker starts on the next frame — the first one that draws it.
      _animate(from: start);
    } else if (controller.value == _stillAt(start)) {
      // That still is already on screen (a spin's end frame): count from now.
      _hold(from: start);
    } else {
      // Show the still now; count from the frame that first draws it.
      controller.value = _stillAt(start);
      final driver = ++_driver;
      SchedulerBinding.instance
        ..addPostFrameCallback((_) {
          if (driver == _driver && !_disposed) _hold(from: start);
        })
        ..ensureVisualUpdate();
    }
    return done.future;
  }

  void _animate({required double from}) {
    final composition = _composition!;
    final driver = ++_driver;
    _holdTimer?.cancel();
    controller.value = from;
    controller
        .animateTo(
          1,
          duration: _framesToDuration(
            composition,
            (1 - from) * composition.durationFrames,
          ),
        )
        .orCancel
        .then<void>(
          (_) {
            if (driver == _driver) _endPass();
          },
          // Stopped by whoever drives the controller next — the flag, a new
          // pass, dispose. The pass is theirs now.
          onError: (Object _) {},
        );
  }

  /// Reduced motion: hold the still for [from], for as long as the frames up
  /// to the next still change (the intro's end) or the pass's end would play.
  void _hold({required double from}) {
    final composition = _composition!;
    final driver = ++_driver;
    _holdTimer?.cancel();
    final introEnd = _introEnd(composition);
    final until = from < introEnd ? introEnd : 1.0;
    final still = _stillAt(from);
    // Set only on change: an equal value would still notify, and repaint.
    if (controller.value != still) {
      controller.value = still;
    } else {
      controller.stop();
    }
    _holdTimer = Timer(
      _framesToDuration(
        composition,
        (until - from) * composition.durationFrames,
      ),
      () {
        if (driver != _driver || _disposed) return;
        if (until < 1) {
          _hold(from: until);
        } else {
          _endPass();
        }
      },
    );
  }

  /// The end frame is on screen: rest on it, then let the screen move on.
  void _endPass() {
    _playing = false;
    _holdTimer = null;
    _restTimer = Timer(rest, () {
      final done = _done;
      _done = null;
      if (!_disposed) done?.complete();
    });
  }

  /// Reduced motion's still for a point of the pass: the middle of the
  /// `wordmark` hold while inside the intro, the end frame — the finished mark
  /// every pass comes to rest on — after it. A file without the markers holds
  /// the end frame throughout.
  double _stillAt(double progress) {
    final composition = _composition!;
    final wordmark = composition.getMarker(wordmarkMarker);
    if (wordmark == null || progress >= _introEnd(composition)) return 1;
    return (wordmark.start + wordmark.end) / 2;
  }

  static double _introEnd(LottieComposition composition) =>
      composition.getMarker(introMarker)?.end ?? 0;

  /// A span of composition frames as wall-clock time.
  static Duration _framesToDuration(
    LottieComposition composition,
    double frames,
  ) => Duration(
    microseconds:
        (frames / composition.frameRate * Duration.microsecondsPerSecond)
            .round(),
  );

  void dispose() {
    _disposed = true;
    ++_driver;
    _holdTimer?.cancel();
    _restTimer?.cancel();
    controller.dispose();
  }
}
