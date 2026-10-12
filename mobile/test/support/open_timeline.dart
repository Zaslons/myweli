import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/screens/provider/auth/pro_splash_screen.dart';
import 'package:myweli/screens/splash/open_animation_player.dart';
import 'package:myweli/screens/splash/splash_screen.dart';

/// An open animation's timeline, read from the asset the way
/// `OpenAnimationPlayer` reads it — so the splash tests follow the file rather
/// than restating its numbers (docs/design/pro-open-animation.md §2.1, §2.8).
class OpenTimeline {
  OpenTimeline._(this._json);

  factory OpenTimeline.load(String asset) => OpenTimeline._(
    jsonDecode(File(asset).readAsStringSync()) as Map<String, dynamic>,
  );

  /// « MyWeli Pro », 142 frames.
  factory OpenTimeline.pro() => OpenTimeline.load(ProSplashScreen.asset);

  /// « MyWeli », 124 frames.
  factory OpenTimeline.consumer() => OpenTimeline.load(SplashScreen.asset);

  /// One frame at 60 fps. A ticker completes on the first frame PAST its
  /// duration, so a pass's end frame is drawn one frame after it — the frame
  /// the rest is counted from.
  static const frame = Duration(microseconds: 16667);

  final Map<String, dynamic> _json;

  num get _fps => _json['fr'] as num;

  Map<String, dynamic> _marker(String name) => (_json['markers'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((m) => m['cm'] == name);

  Duration _frames(num frames) =>
      Duration(microseconds: (frames / _fps * 1e6).round());

  /// The composition's length as lottie plays it: it ends at `op - 0.01`.
  num get _durationFrames => endFrame - 0.01 - (_json['ip'] as num);

  /// How long the intro plays (wordmark → morph): reduced motion's wordmark
  /// still lasts this long.
  Duration get intro =>
      _frames(_marker(OpenAnimationPlayer.introMarker)['dr'] as num);

  /// The whole file, played once — the first pass, before its rest.
  Duration get firstPass => _frames(_durationFrames);

  /// One spin: the `loop` marker's start to the end frame, before its rest.
  Duration get spin => _frames(_durationFrames - loopStartFrame);

  /// The composition's last frame (`op`).
  num get endFrame => _json['op'] as num;

  /// A controller value as a composition frame (±0.01: lottie ends the
  /// composition at `op - 0.01`).
  double frameOf(double progress) => progress * endFrame;

  /// First frame of the spin.
  num get loopStartFrame =>
      _marker(OpenAnimationPlayer.loopMarker)['tm'] as num;

  /// The `wordmark` hold, in frames.
  (num, num) get wordmarkFrames {
    final m = _marker(OpenAnimationPlayer.wordmarkMarker);
    return (m['tm'] as num, (m['tm'] as num) + (m['dr'] as num));
  }
}

/// The composition's first frame — the ticker's first tick, the moment every
/// pass is timed from. `onLoaded` runs once the decode lands (with the test
/// bundle, already at the end of `pumpWidget`; a slower decode, on the next
/// flush), and the frame AFTER it is the first to draw the composition. Two
/// zero-length pumps cover both orders: after them the composition has been
/// drawn and no time has passed, so the clock starts where the test thinks.
Future<void> pumpFirstFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}
