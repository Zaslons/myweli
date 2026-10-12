import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:myweli/screens/provider/auth/pro_splash_screen.dart';

/// The Pro open animation's composition contract
/// (docs/design/pro-open-animation.md).
///
/// `ProSplashScreen` reads its whole timeline from this file's markers, and a
/// designer may replace the file later — so what the screen relies on is
/// pinned here, against the consumer file it was derived from.
void main() {
  Map<String, dynamic> load(String name) =>
      jsonDecode(File('assets/lottie/open/$name').readAsStringSync())
          as Map<String, dynamic>;

  final pro = load('myweli_loader_mixed_pro.json');
  final consumer = load('myweli_loader_mixed.json');

  List<Map<String, dynamic>> layersOf(Map<String, dynamic> c) =>
      (c['layers'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> layer(Map<String, dynamic> c, String name) =>
      layersOf(c).firstWhere((l) => l['nm'] == name);
  Map<String, num> marker(String name, [Map<String, dynamic>? file]) {
    final m = ((file ?? pro)['markers'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((m) => m['cm'] == name);
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

  /// Every static path of a glyph layer.
  List<Map<String, dynamic>> paths(Map<String, dynamic> l) => [
    for (final group in l['shapes'] as List)
      for (final item in (group as Map)['it'] as List)
        if ((item as Map)['ty'] == 'sh')
          (item['ks'] as Map)['k'] as Map<String, dynamic>,
  ];
  Iterable<num> xs(Map<String, dynamic> p) =>
      (p['v'] as List).map((v) => (v as List)[0] as num);
  Iterable<num> ys(Map<String, dynamic> p) =>
      (p['v'] as List).map((v) => (v as List)[1] as num);
  num minOf(Iterable<num> v) => v.reduce((a, b) => a < b ? a : b);
  num maxOf(Iterable<num> v) => v.reduce((a, b) => a > b ? a : b);

  const letters = ['M', 'W', 'L_y', 'L_e', 'L_l', 'L_i', 'L_P', 'L_r', 'L_o'];

  /// Walks [path] (map keys and list indices) down a decoded JSON tree.
  T dig<T>(Object? node, List<Object> path) {
    var at = node;
    for (final step in path) {
      at = step is int ? (at! as List)[step] : (at! as Map)[step];
    }
    return at as T;
  }

  /// The M/W path keyframes (the letter, held, then the morph to the mark).
  List<Map<String, dynamic>> morph(Map<String, dynamic> c, String name) =>
      dig<List<dynamic>>(layer(c, name), [
        'shapes', 0, 'it', 0, 'ks', 'k', //
      ]).cast<Map<String, dynamic>>();

  /// The first path of a keyframe's `s`.
  Map<String, dynamic> pathOf(Map<String, dynamic> kf) =>
      dig<Map<String, dynamic>>(kf, ['s', 0]);

  test('the screen points at this file', () {
    expect(
      ProSplashScreen.asset,
      'assets/lottie/open/myweli_loader_mixed_pro.json',
    );
  });

  test('shape layers only — « Pro » is paths, never a font or text layer', () {
    expect(layersOf(pro).map((l) => l['nm']), ['redraw', ...letters]);
    expect(layersOf(pro).map((l) => l['ty']).toSet(), {4});
    expect(pro.containsKey('fonts'), isFalse);
    expect(pro.containsKey('chars'), isFalse);
    expect((pro['assets'] as List), isEmpty);
    expect(
      [pro['w'], pro['h'], pro['fr'], pro['ip'], pro['op']],
      [560, 380, 25, 0, 142],
    );
  });

  test(
    'markers: intro then loop, back to back to the end; wordmark inside intro',
    () {
      final intro = marker(ProSplashScreen.introMarker);
      final loop = marker(ProSplashScreen.loopMarker);
      final wordmark = marker(ProSplashScreen.wordmarkMarker);
      expect(intro, {'start': 0, 'end': 74});
      expect(loop, {'start': 74, 'end': 142});
      expect(wordmark, {'start': 12, 'end': 38});
      expect(
        loop['end'],
        pro['op'],
        reason: 'the loop must run to the last frame',
      );
    },
  );

  test(
    'lottie decodes it and resolves every marker the screen reads',
    () async {
      final composition = await LottieComposition.fromBytes(
        File(
          'assets/lottie/open/myweli_loader_mixed_pro.json',
        ).readAsBytesSync(),
      );
      // lottie ends a composition at `op - 0.01` (the last frame exclusive).
      expect(composition.durationFrames, closeTo(142, 0.02));
      expect(composition.frameRate, 25);
      for (final name in [
        ProSplashScreen.introMarker,
        ProSplashScreen.wordmarkMarker,
        ProSplashScreen.loopMarker,
      ]) {
        expect(composition.getMarker(name), isNotNull, reason: name);
      }
    },
  );

  test('« MyWeli Pro » holds fully legible for ≥ 1.0 s before fade/morph', () {
    final wordmark = marker(ProSplashScreen.wordmarkMarker);
    final start = wordmark['start']!;
    final end = wordmark['end']!;
    expect((end - start) / (pro['fr'] as num), greaterThanOrEqualTo(1.0));

    for (final name in letters) {
      final l = layer(pro, name);
      expect(l['ip'] as num, lessThanOrEqualTo(start), reason: name);
      expect(l['op'] as num, greaterThanOrEqualTo(end), reason: name);
      // Every keyframe from the last one at/before `start` to the first one
      // at/after `end` is 100 — so the eased value in between is 100 too.
      final kfs = opacity(l);
      final from = kfs.lastIndexWhere((k) => k[0] <= start);
      final to = kfs.indexWhere((k) => k[0] >= end);
      expect(from, isNonNegative, reason: name);
      expect(to, greaterThan(from), reason: name);
      for (final k in kfs.sublist(from, to + 1)) {
        expect(k[1], 100, reason: '$name at frame ${k[0]}');
      }
    }

    // …and M/W have not started morphing: their path is still the letter.
    for (final name in ['M', 'W']) {
      final kfs = morph(pro, name);
      final letter = kfs.first['s'];
      for (final k in kfs.where((k) => (k['t'] as num) <= end)) {
        expect(k['s'], letter, reason: '$name morphs at frame ${k['t']}');
      }
      expect(
        kfs.where((k) => (k['t'] as num) > end),
        isNotEmpty,
        reason: '$name must still morph after the hold',
      );
    }
  });

  test('« Pro » fades exactly like the lowercase letters', () {
    final e = layer(pro, 'L_e');
    for (final name in ['L_P', 'L_r', 'L_o']) {
      final l = layer(pro, name);
      expect(opacity(l), opacity(e), reason: name);
      expect([l['ip'], l['op']], [e['ip'], e['op']], reason: name);
      Object fill(Map<String, dynamic> x) => dig<List<dynamic>>(x, [
        'shapes', 0, 'it', //
      ]).cast<Map<String, dynamic>>().where((i) => i['ty'] == 'fl').single;
      expect(fill(l), fill(e), reason: '$name fill (colour, opacity, rule)');
    }
  });

  test('« Pro » sits on the same baseline, cap height and stem weight', () {
    final p = paths(layer(pro, 'L_P'));
    final r = paths(layer(pro, 'L_r')).single;
    final o = paths(layer(pro, 'L_o'));
    final l = paths(layer(pro, 'L_l')).single;
    final e = paths(layer(pro, 'L_e'));
    final mLetter = pathOf(morph(pro, 'M').first);

    expect(
      maxOf(ys(p.first)),
      closeTo(maxOf(ys(l)), 0.01),
      reason: 'P baseline',
    );
    expect(maxOf(ys(r)), closeTo(maxOf(ys(l)), 0.01), reason: 'r baseline');
    expect(
      maxOf(ys(o.first)),
      closeTo(maxOf(ys(e.first)), 0.05),
      reason: 'o overshoots the baseline like e',
    );
    expect(
      minOf(ys(p.first)),
      closeTo(minOf(ys(mLetter)), 0.05),
      reason: 'P cap height = M',
    );
    expect(
      minOf(ys(r)),
      closeTo(minOf(ys(e.first)), 0.05),
      reason: 'r x-height = e',
    );
    final stemP = minOf(xs(p[1])) - minOf(xs(p.first));
    final stemL = maxOf(xs(l)) - minOf(xs(l));
    expect(stemP, closeTo(stemL, 0.3), reason: 'P stem = l stem (Medium)');
  });

  test('a real word space, and the whole wordmark recentred', () {
    final i = paths(layer(pro, 'L_i'));
    final l = paths(layer(pro, 'L_l')).single;
    final p = paths(layer(pro, 'L_P'));
    final o = paths(layer(pro, 'L_o'));
    final iRight = maxOf(i.expand(xs));
    final letterGap = minOf(i.expand(xs)) - maxOf(xs(l));
    final wordGap = minOf(xs(p.first)) - iRight;
    expect(wordGap, greaterThan(2 * letterGap), reason: '« MyWeliPro »');

    final mLetter = pathOf(morph(pro, 'M').first);
    final stroke = dig<num>(layer(pro, 'M'), [
      'shapes', 0, 'it', 1, 'w', 'k', 0, 's', 0, //
    ]);
    final halfStroke = stroke / 2;
    final left = minOf(xs(mLetter)) - halfStroke;
    final right = maxOf(o.expand(xs));
    expect((left + right) / 2, closeTo((pro['w'] as num) / 2, 0.5));
  });

  test('the mark end-state and the redraw are the consumer\'s, untouched', () {
    // The consumer's `loop` starts at 56; everything from there on moved later
    // by the wordmark hold, and by nothing else.
    final shift =
        marker(ProSplashScreen.loopMarker)['start']! -
        marker(ProSplashScreen.loopMarker, consumer)['start']!;
    expect(shift, 18);

    Object? retimed(Object? node, num by) => switch (node) {
      final Map m => {
        for (final e in m.entries)
          e.key:
              (e.key == 't' || e.key == 'ip' || e.key == 'op') && e.value is num
              ? ((e.value as num) + by).toStringAsFixed(4)
              : retimed(e.value, by),
      },
      final List v => [for (final x in v) retimed(x, by)],
      _ => node,
    };

    expect(
      retimed(layer(pro, 'redraw'), 0),
      retimed(layer(consumer, 'redraw'), shift),
    );
    for (final name in ['M', 'W']) {
      final mine = morph(pro, name).last;
      final theirs = morph(consumer, name).last;
      expect(mine['s'], theirs['s'], reason: '$name mark path');
      expect(
        mine['t'],
        (theirs['t'] as num) + shift,
        reason: '$name morph end',
      );
    }
  });

  test(
    'M/W stay on screen until the redraw is in — no blank hand-off frame',
    () {
      // The consumer file used to drop M/W to 0 over [53, 54] with the redraw
      // in at 54: lottie renders index 54 a hair early, so one 40 ms frame was
      // empty (fixed 2026-10-12; both files are also RENDERED frame by frame
      // in `open_animation_asset_test`).
      final redrawIn = layer(pro, 'redraw')['ip'] as num;
      for (final name in ['M', 'W']) {
        final kfs = opacity(layer(pro, name));
        final lastFull = kfs.lastWhere((k) => k[1] == 100);
        expect(lastFull[0], greaterThanOrEqualTo(redrawIn), reason: name);
      }
    },
  );
}
