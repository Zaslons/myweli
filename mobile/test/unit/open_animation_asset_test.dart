import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:myweli/screens/provider/auth/pro_splash_screen.dart';
import 'package:myweli/screens/splash/open_animation_player.dart';
import 'package:myweli/screens/splash/splash_screen.dart';

/// The consumer open animation's contract, and what BOTH open animations
/// must render (docs/design/pro-open-animation.md §2.1, §2.8).
///
/// `OpenAnimationPlayer` reads its timeline from the markers, and the splash
/// leaves on the end frame — so the markers, the end frame and the hand-off
/// into the spin are pinned here. The Pro file's own contract (the « Pro »
/// glyphs, its re-timing) lives in `pro_open_animation_asset_test`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> load(String asset) =>
      jsonDecode(File(asset).readAsStringSync()) as Map<String, dynamic>;

  final consumer = load(SplashScreen.asset);

  Map<String, dynamic> layer(Map<String, dynamic> c, String name) =>
      (c['layers'] as List).cast<Map<String, dynamic>>().firstWhere(
        (l) => l['nm'] == name,
      );
  Map<String, num> marker(Map<String, dynamic> c, String name) {
    final m = (c['markers'] as List).cast<Map<String, dynamic>>().firstWhere(
      (m) => m['cm'] == name,
    );
    return {
      'start': m['tm'] as num,
      'end': (m['tm'] as num) + (m['dr'] as num),
    };
  }

  /// Opacity keyframes as `[frame, value]` pairs.
  List<List<num>> opacity(Map<String, dynamic> l) => [
    for (final k in ((l['ks'] as Map)['o'] as Map)['k'] as List)
      [(k as Map)['t'] as num, (k['s'] as List).first as num],
  ];

  /// The M/W path keyframes (the letter, held, then the morph to the mark).
  List<Map<String, dynamic>> morph(Map<String, dynamic> c, String name) {
    final group = (layer(c, name)['shapes'] as List).first as Map;
    final path = (group['it'] as List).first as Map;
    return ((path['ks'] as Map)['k'] as List).cast<Map<String, dynamic>>();
  }

  test('the screen points at this file', () {
    expect(SplashScreen.asset, 'assets/lottie/open/myweli_loader_mixed.json');
  });

  test(
    'markers: intro then loop, back to back to the end; wordmark inside',
    () {
      final intro = marker(consumer, OpenAnimationPlayer.introMarker);
      final wordmark = marker(consumer, OpenAnimationPlayer.wordmarkMarker);
      final loop = marker(consumer, OpenAnimationPlayer.loopMarker);
      expect(
        [consumer['fr'], consumer['ip'], consumer['op']],
        [25, 0, 124],
        reason: '124 frames at 25 fps: the 4.96 s first pass',
      );
      expect(intro, {'start': 0, 'end': 56});
      expect(wordmark, {'start': 12, 'end': 20});
      expect(loop, {'start': 56, 'end': 124});
      expect(loop['end'], consumer['op'], reason: 'the spin runs to the end');
    },
  );

  test('the wordmark marker is a hold: every letter at 100 %, M/W letters', () {
    final wordmark = marker(consumer, OpenAnimationPlayer.wordmarkMarker);
    final start = wordmark['start']!;
    final end = wordmark['end']!;
    for (final name in ['M', 'W', 'L_y', 'L_e', 'L_l', 'L_i']) {
      final kfs = opacity(layer(consumer, name));
      final from = kfs.lastIndexWhere((k) => k[0] <= start);
      final to = kfs.indexWhere((k) => k[0] >= end);
      expect(from, isNonNegative, reason: name);
      expect(to, greaterThan(from), reason: name);
      for (final k in kfs.sublist(from, to + 1)) {
        expect(k[1], 100, reason: '$name at frame ${k[0]}');
      }
    }
    for (final name in ['M', 'W']) {
      final kfs = morph(consumer, name);
      for (final k in kfs.where((k) => (k['t'] as num) <= end)) {
        expect(k['s'], kfs.first['s'], reason: '$name morphs at ${k['t']}');
      }
    }
  });

  test('M/W stay on screen until the redraw is in — the keyframes', () {
    // They used to drop to 0 over [53, 54] with the redraw in at 54: lottie
    // draws index 54 at 53.996 (`op - 0.01`), where neither is there.
    final redrawIn = layer(consumer, 'redraw')['ip'] as num;
    for (final name in ['M', 'W']) {
      final lastFull = opacity(
        layer(consumer, name),
      ).lastWhere((k) => k[1] == 100);
      expect(lastFull[0], greaterThanOrEqualTo(redrawIn), reason: name);
    }
  });

  test(
    'lottie decodes it and resolves every marker the player reads',
    () async {
      final composition = await LottieComposition.fromBytes(
        File(SplashScreen.asset).readAsBytesSync(),
      );
      expect(composition.durationFrames, closeTo(124, 0.02));
      for (final name in [
        OpenAnimationPlayer.introMarker,
        OpenAnimationPlayer.wordmarkMarker,
        OpenAnimationPlayer.loopMarker,
      ]) {
        expect(composition.getMarker(name), isNotNull, reason: name);
      }
    },
  );

  // ── What the user SEES, rendered the way lottie draws it on a phone. ──────
  //
  // A keyframe check reads the designer's intent; the blank frame was in the
  // gap between that intent and lottie's frame rounding. So both files are
  // also drawn, frame by frame, and the ink counted.
  for (final asset in [SplashScreen.asset, ProSplashScreen.asset]) {
    group(asset.split('/').last, () {
      late LottieComposition composition;
      setUpAll(() async {
        composition = await LottieComposition.fromBytes(
          File(asset).readAsBytesSync(),
        );
      });

      int frames() => (composition.durationFrames + 0.01).round();

      test(
        'every frame from the wordmark to the spin has ink — no blank hand-off',
        () async {
          final from = composition.getMarker(
            OpenAnimationPlayer.wordmarkMarker,
          )!;
          final to = composition.getMarker(OpenAnimationPlayer.loopMarker)!;
          final finished = _ink(await _draw(composition, 1));
          final first = (from.start * frames()).round();
          final last = (to.start * frames()).round();
          for (var k = first; k <= last; k++) {
            final ink = _ink(await _draw(composition, (k + 0.5) / frames()));
            expect(
              ink,
              greaterThan(finished ~/ 3),
              reason:
                  'frame $k, as lottie draws it, is all but empty ($ink of '
                  "the finished mark's $finished ink pixels)",
            );
          }
        },
      );

      test(
        'the end frame is the finished mark — the spin\'s first picture',
        () async {
          // The splash leaves on the end frame, and a pending Pro session
          // restarts the spin from `loop` — so the two must be the same picture
          // (no jump), and it must be the mark, not an erased one.
          final loop = composition.getMarker(OpenAnimationPlayer.loopMarker)!;
          final end = await _draw(composition, 1);
          final start = await _draw(
            composition,
            (loop.start * frames() + 0.5) / frames(),
          );
          expect(_ink(end), greaterThan(0), reason: 'an empty end frame');
          expect(
            end,
            start,
            reason: 'the end frame and the spin\'s first frame differ',
          );
        },
      );
    });
  }
}

/// [composition] at [progress], drawn as `Lottie` draws it (composition
/// frame rate — the default), as RGBA bytes.
Future<Uint8List> _draw(LottieComposition composition, double progress) async {
  const size = Size(280, 190);
  final drawable = LottieDrawable(composition)..setProgress(progress);
  final recorder = ui.PictureRecorder();
  drawable.draw(ui.Canvas(recorder), Offset.zero & size);
  final image = await recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final bytes = await image.toByteData();
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// Pixels at least half opaque.
int _ink(Uint8List rgba) {
  var ink = 0;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] >= 128) ink++;
  }
  return ink;
}
