import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/router/admin_router.dart';
import 'package:myweli/core/router/app_router.dart';
import 'package:myweli/core/router/pro_router.dart';
import 'package:myweli/providers/admin/admin_auth_provider.dart';

/// Every route a screen pushes exists in the router of every app that can
/// reach that screen (docs/design/salon-location-map.md §8).
///
/// **Why this exists.** On 2026-08-22 (#491) the consumer map route was
/// renamed `/favorites` → `/carte`. Two screens kept pushing `/favorites` —
/// the salon page's « Voir sur la carte » and the one in Mes rendez-vous — and
/// for seven weeks both landed on go_router's « Page Not Found ». Nothing in
/// the suite read the target of a `push`. The salon page is also the pro
/// « Aperçu », whose router has no map at all.
///
/// **What it reads.** The code of `lib/` with comments blanked (string-aware:
/// the `//` of `'https://…'` is not a comment), then every argument of a
/// `.push(` / `.go(` / `.pushReplacement(` / `.replace(` — and `*Named(` —
/// that is not a `Navigator` call, plus every relative `Uri(path: …)`. Inside
/// those it takes every string literal starting with `/`: both branches of a
/// ternary, the default of a `??`, and the `returnTo` nested in an
/// interpolation. The path is the text before `?`; an interpolation is a
/// wildcard segment that only a `:param` can match.
///
/// **Against what.** The REAL routers (`AppRouter.router`, `ProRouter.router`,
/// `createAdminRouter`), walked — nested routes composed — not re-parsed. An
/// app reaches a file when its entry point imports it, transitively.
///
/// **What it cannot see** is a runtime branch: `ProviderDetailScreen` is
/// imported by the pro app for the owner « Aperçu », where every consumer
/// navigation is behind `widget.preview`. Those are [_exempt], one by one,
/// each with its reason, and an exemption that no longer matches anything
/// fails — so the table cannot quietly outlive the code. The `/carte` one is
/// held behaviourally by `salon_location_map_test.dart` (preview → the
/// map-app picker, the router never moves).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final source = {
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')))
      f.path.replaceAll(r'\', '/'): blankComments(f.readAsStringSync()),
  };

  final entries = {
    'consumer': 'lib/main.dart',
    'pro': 'lib/main_pro.dart',
    'admin': 'lib/main_admin.dart',
  };

  // Built inside the test zone: the admin router's auth provider opens an
  // HTTP client, which `flutter test` only allows there.
  late final Map<String, GoRouter> routers;
  setUpAll(() {
    routers = {
      'consumer': AppRouter.router,
      'pro': ProRouter.router,
      'admin': createAdminRouter(AdminAuthProvider()),
    };
  });

  final reach = {
    for (final e in entries.entries) e.key: reachable(e.value, source),
  };
  final navs = {
    for (final e in source.entries) e.key: scanNavigations(e.value),
  };

  /// `app · file · path` for every navigation that does not resolve and is
  /// not exempt; [used] collects the exemptions that matched.
  List<String> offenders(Set<String> used) {
    final out = <String>[];
    for (final app in entries.keys) {
      final templates = routeTemplates(routers[app]!);
      final names = routeNames(routers[app]!);
      for (final file in reach[app]!.toList()..sort()) {
        for (final nav in navs[file]!) {
          final ok = nav.isName
              ? names.contains(nav.target)
              : resolves(nav.target, templates);
          if (ok) continue;
          final shown = nav.shown;
          if (_exempt[app]?[file]?.containsKey(shown) ?? false) {
            used.add('$app · $file · $shown');
            continue;
          }
          out.add('$app · $file · $shown');
        }
      }
    }
    return out;
  }

  group('the scanner (positive controls)', () {
    test('it finds /favorites — the target that went dead', () {
      final found = scanNavigations(
        blankComments(
          r"onTap: () => context.push('/favorites?providerId=${p.id}'),",
        ),
      );
      expect(found.map((n) => n.target), ['/favorites']);
      expect(
        resolves('/favorites', routeTemplates(AppRouter.router)),
        isFalse,
        reason: 'the consumer router no longer has it — and must say so',
      );
      expect(resolves('/carte', routeTemplates(AppRouter.router)), isTrue);
    });

    test('a comment is not code — even one that quotes a push', () {
      final src = blankComments('''
// context.push('/nowhere');
/* context.go('/nowhere-either'); */
/// Was `context.push('/favorites')`.
final u = 'https://example.com/a'; // context.go('/trailing')
''');
      expect(scanNavigations(src), isEmpty);
      // …and the URL survived: `//` inside a string is not a comment.
      expect(src, contains("'https://example.com/a'"));
    });

    test('ternaries, ?? defaults and nested returnTo are all read', () {
      final found = scanNavigations(
        blankComments(r"""
context.go(auth.isStaff ? '/pro/staff' : (widget.returnTo ?? '/pro/dashboard'));
context.go('/login?returnTo=${Uri.encodeComponent('/carte')}');
context.push(
  '/pro/clients/$id',
);
context.push(Uri(path: '/booking/confirm', queryParameters: qs).toString());
final returnUrl = Uri(path: '/booking', queryParameters: {'a': 'b'});
final api = Uri(scheme: 'https', host: 'x', path: '/not-a-route');
"""),
      ).map((n) => n.shown);
      expect(
        found,
        unorderedEquals([
          '/pro/staff',
          '/pro/dashboard',
          '/carte',
          '/login',
          '/pro/clients/{}',
          '/booking/confirm',
          '/booking/confirm', // the Uri inside the push, read once each way
          '/booking',
        ]),
      );
    });

    test('Navigator calls and API Uris are not routes', () {
      final found = scanNavigations(
        blankComments('''
Navigator.of(context).push(MaterialPageRoute(builder: (_) => X('/a')));
Navigator.push(context, MaterialPageRoute(builder: (_) => X('/b')));
final u = _uri('/providers').replace(queryParameters: {'page': '1'});
'''),
      );
      expect(found, isEmpty);
    });

    test('a named navigation is checked against route names', () {
      final found = scanNavigations(blankComments("context.goNamed('carte');"));
      expect(found.single.isName, isTrue);
      expect(routeNames(AppRouter.router), contains('carte'));
      expect(routeNames(AppRouter.router), isNot(contains('favorites')));
    });

    test('an interpolated segment matches a :param, never a literal', () {
      final t = routeTemplates(AppRouter.router);
      expect(resolves('/appointment/\u0000', t), isTrue);
      expect(resolves('/provider/\u0000', t), isTrue);
      expect(resolves('/profile/\u0000', t), isFalse);
      expect(resolves('/profile/edit', t), isTrue, reason: 'a nested route');
    });
  });

  group('the corpus is real', () {
    test('each app reaches its screens and pushes routes', () {
      expect(source.length, greaterThan(100));
      int count(String app) =>
          reach[app]!.fold(0, (n, f) => n + navs[f]!.length);
      // Measured 2026-10-12: 50 · 68 · 7 navigations, over 205 · 236 · 68
      // reachable files. A scanner that lost a call shape drops below these.
      expect(count('consumer'), greaterThan(40));
      expect(count('pro'), greaterThan(55));
      expect(count('admin'), greaterThan(5));
      expect(reach['consumer'], contains('lib/screens/map/map_screen.dart'));
      expect(reach['pro'], isNot(contains('lib/screens/map/map_screen.dart')));
      expect(
        reach['pro'],
        contains('lib/screens/providers/provider_detail_screen.dart'),
        reason: 'the « Aperçu » — the reason this test reads per app',
      );
    });

    test('each entry point is the one its router belongs to', () {
      expect(source['lib/main.dart'], contains('AppRouter.router'));
      expect(source['lib/main_pro.dart'], contains('ProRouter.router'));
      expect(source['lib/main_admin.dart'], contains('createAdminRouter('));
      final mains = source.entries
          .where(
            (e) => RegExp(
              r'^(?:Future<void>|void)\s+main\(',
              multiLine: true,
            ).hasMatch(e.value),
          )
          .map((e) => e.key)
          .toSet();
      expect(mains, entries.values.toSet());
    });

    test('the routers are read whole, nested routes included', () {
      expect(
        routeTemplates(AppRouter.router),
        containsAll(['/carte', '/profile/data']),
      );
      expect(routeTemplates(ProRouter.router), contains('/pro/apercu'));
      expect(routeTemplates(ProRouter.router), isNot(contains('/carte')));
    });
  });

  test('every pushed route exists in every app that can push it', () {
    final used = <String>{};
    expect(
      offenders(used),
      isEmpty,
      reason:
          'a screen pushes a route its app does not register — go_router '
          'shows « Page Not Found ». Register the route, fix the path, or — '
          'only for a branch the app can never take — add it to _exempt '
          'with the reason.',
    );
  });

  test('no exemption outlives the code it excused', () {
    final used = <String>{};
    offenders(used);
    final declared = {
      for (final MapEntry(key: app, value: files) in _exempt.entries)
        for (final MapEntry(key: file, value: paths) in files.entries)
          for (final path in paths.keys) '$app · $file · $path',
    };
    expect(declared.difference(used), isEmpty);
  });
}

/// Navigations an app's import graph reaches but a runtime branch never
/// takes — `app → file → shown path → why`. Keep it short; every line is a
/// promise this test cannot check by itself.
const _exempt = <String, Map<String, Map<String, String>>>{
  'pro': {
    // The owner « Aperçu » (/pro/apercu → ProviderDetailScreen(preview: true)).
    'lib/screens/providers/provider_detail_screen.dart': {
      '/login':
          'the favourite heart — `if (!widget.preview) _favoriteAction()`',
      '/bookings':
          '« Voir tout » of « Vos rendez-vous ici » — the whole card is '
          '`if (!widget.preview)` (salon-rating-new-and-visits-card.md §2.3)',
      '/appointment/{}':
          'the visit tiles — same `if (!widget.preview)`; the preview shows no card',
      '/booking':
          '« Réserver » and « Réserver à nouveau » — the preview’s CTA is disabled',
      '/carte':
          '« Voir sur la carte » — `_openOnMap` opens the map-app picker when '
          '`widget.preview`; held by salon_location_map_test.dart',
    },
    // ProSplashScreen reads one constant, `SplashScreen.animationWidth`; the
    // consumer splash itself is never built in the pro app.
    'lib/screens/splash/splash_screen.dart': {
      '/home': 'constant-only import (SplashScreen.animationWidth)',
    },
  },
};

/// One navigation target: a path (or a route name, [isName]) as written,
/// interpolations as `\u0000`.
class Nav {
  Nav(this.target, {this.isName = false});
  final String target;
  final bool isName;

  /// The target as a person reads it — `/appointment/{}`.
  String get shown => target.replaceAll('\u0000', '{}');

  @override
  String toString() => shown;
}

/// Every route template of [router] — nested paths composed onto their
/// parent's.
List<String> routeTemplates(GoRouter router) {
  final out = <String>[];
  void walk(List<RouteBase> routes, String parent) {
    for (final route in routes) {
      var here = parent;
      if (route is GoRoute) {
        here = route.path.startsWith('/')
            ? route.path
            : '${parent == '/' ? '' : parent}/${route.path}';
        out.add(here);
      }
      walk(route.routes, here);
    }
  }

  walk(router.configuration.routes, '');
  return out;
}

Set<String> routeNames(GoRouter router) {
  final out = <String>{};
  void walk(List<RouteBase> routes) {
    for (final route in routes) {
      if (route is GoRoute && route.name != null) out.add(route.name!);
      walk(route.routes);
    }
  }

  walk(router.configuration.routes);
  return out;
}

/// Does [path] (`\u0000` = an interpolation) land on one of [templates]?
/// A `:param` takes any non-empty segment; an interpolated segment matches a
/// `:param` only — `/profile/$x` is not `/profile/edit` just because it
/// might be.
bool resolves(String path, Iterable<String> templates) {
  final segments = path.split('/');
  for (final t in templates) {
    final ts = t.split('/');
    if (ts.length != segments.length) continue;
    var ok = true;
    for (var k = 0; k < ts.length && ok; k++) {
      if (ts[k].startsWith(':')) {
        ok = segments[k].isNotEmpty;
      } else {
        ok = segments[k] == ts[k];
      }
    }
    if (ok) return true;
  }
  return false;
}

/// The files [entry] imports, transitively (`import`/`export`/`part`, relative
/// or `package:myweli/`). [source] is comment-blanked.
Set<String> reachable(String entry, Map<String, String> source) {
  final directive = RegExp(
    r'^\s*(?:import|export|part)\s+([^;]+);',
    multiLine: true,
  );
  final uri = RegExp(r"""['"]([^'"]+\.dart)['"]""");
  final seen = {entry};
  final todo = [entry];
  while (todo.isNotEmpty) {
    final file = todo.removeLast();
    final dir = file.substring(0, file.lastIndexOf('/'));
    for (final d in directive.allMatches(source[file] ?? '')) {
      for (final u in uri.allMatches(d.group(1)!)) {
        final target = _resolve(dir, u.group(1)!);
        if (target != null && source.containsKey(target) && seen.add(target)) {
          todo.add(target);
        }
      }
    }
  }
  return seen;
}

String? _resolve(String dir, String uri) {
  if (uri.startsWith('package:myweli/')) {
    return 'lib/${uri.substring('package:myweli/'.length)}';
  }
  if (uri.contains(':')) return null; // dart:, other packages
  final parts = [...dir.split('/'), ...uri.split('/')];
  final out = <String>[];
  for (final p in parts) {
    if (p == '..') {
      out.removeLast();
    } else if (p != '.' && p.isNotEmpty) {
      out.add(p);
    }
  }
  return out.join('/');
}

final _navCall = RegExp(
  r'\.(push|go|pushReplacement|replace|pushNamed|goNamed|pushReplacementNamed|replaceNamed)\s*(?:<[^<>()]*>)?\s*\(',
);
final _navigatorReceiver = RegExp(
  r'\bNavigator(?:\s*\.\s*of\s*\([^()]*\))?\s*$',
);
final _relativeUri = RegExp(r'(?<![\w.])Uri\s*\(');

/// The navigations in [code] (comment-blanked).
List<Nav> scanNavigations(String code) {
  final out = <Nav>[];
  for (final m in _navCall.allMatches(code)) {
    final before = code.substring(max(0, m.start - 80), m.start);
    if (_navigatorReceiver.hasMatch(before)) continue;
    final open = m.end - 1;
    final args = code.substring(open + 1, _closeParen(code, open));
    if (m.group(1)!.endsWith('Named')) {
      final first = RegExp(r'''^\s*['"]''').hasMatch(args)
          ? stringLiterals(args).firstOrNull
          : null;
      if (first != null) out.add(Nav(first, isName: true));
      continue;
    }
    for (final s in stringLiterals(args)) {
      if (s.startsWith('/')) out.add(Nav(_pathOf(s)));
    }
  }
  // An app location built as a relative Uri, then pushed as a string.
  for (final m in _relativeUri.allMatches(code)) {
    final open = m.end - 1;
    final args = code.substring(open + 1, _closeParen(code, open));
    if (RegExp(r'\b(?:scheme|host)\s*:').hasMatch(args)) continue;
    final path = RegExp(r'''\bpath\s*:\s*(?=['"])''').firstMatch(args);
    if (path == null) continue;
    final s = stringLiterals(args.substring(path.end)).firstOrNull;
    if (s != null && s.startsWith('/')) out.add(Nav(_pathOf(s)));
  }
  return out;
}

String _pathOf(String literal) {
  final cut = literal.indexOf(RegExp(r'[?#]'));
  return cut < 0 ? literal : literal.substring(0, cut);
}

/// [src] with every comment replaced by spaces — same length, newlines kept.
/// String-aware, interpolations included.
String blankComments(String src) {
  final out = src.split('');
  _DartWalker(
    src,
    onComment: (from, to) {
      for (var k = from; k < to; k++) {
        if (out[k] != '\n') out[k] = ' ';
      }
    },
  ).code(0);
  return out.join();
}

/// The static text of every string literal in [code], nested ones (inside
/// `${…}`) included; each interpolation is `\u0000`.
List<String> stringLiterals(String code) {
  final found = <(int, String)>[];
  _DartWalker(
    code,
    onString: (start, text) => found.add((start, text)),
  ).code(0);
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final f in found) f.$2];
}

/// The index of the `)` closing the `(` at [open] — strings skipped.
int _closeParen(String code, int open) {
  var depth = 0;
  var i = open;
  final walker = _DartWalker(code);
  while (i < code.length) {
    final c = code[i];
    if (c == "'" || c == '"') {
      i = walker.string(i, raw: false);
      continue;
    }
    if (c == 'r' &&
        i + 1 < code.length &&
        (code[i + 1] == "'" || code[i + 1] == '"') &&
        !_DartWalker._ident(code[i - 1])) {
      i = walker.string(i + 1, raw: true);
      continue;
    }
    if (c == '(') depth++;
    if (c == ')' && --depth == 0) return i;
    i++;
  }
  return code.length;
}

/// A just-enough Dart lexer: comments, strings (single, double, triple, raw)
/// and `${…}` / `$name` interpolations, which contain code.
class _DartWalker {
  _DartWalker(this.s, {this.onComment, this.onString});

  final String s;
  final void Function(int from, int to)? onComment;
  final void Function(int start, String text)? onString;

  static bool _ident(String c) => RegExp(r'[A-Za-z0-9_]').hasMatch(c);
  static bool _identStart(String c) => RegExp(r'[A-Za-z_]').hasMatch(c);

  /// Code from [i] to the end — or, [interpolation], past the `}` closing
  /// it. Returns where it stopped.
  int code(int i, {bool interpolation = false}) {
    var depth = 0;
    while (i < s.length) {
      final c = s[i];
      if (s.startsWith('//', i)) {
        final nl = s.indexOf('\n', i);
        final end = nl < 0 ? s.length : nl;
        onComment?.call(i, end);
        i = end;
      } else if (s.startsWith('/*', i)) {
        var d = 1;
        var j = i + 2;
        while (j < s.length && d > 0) {
          if (s.startsWith('/*', j)) {
            d++;
            j += 2;
          } else if (s.startsWith('*/', j)) {
            d--;
            j += 2;
          } else {
            j++;
          }
        }
        onComment?.call(i, j);
        i = j;
      } else if (c == "'" || c == '"') {
        i = string(i, raw: false);
      } else if (c == 'r' &&
          i + 1 < s.length &&
          (s[i + 1] == "'" || s[i + 1] == '"') &&
          (i == 0 || !_ident(s[i - 1]))) {
        i = string(i + 1, raw: true);
      } else if (c == '{') {
        depth++;
        i++;
      } else if (c == '}') {
        if (interpolation && depth == 0) return i + 1;
        depth--;
        i++;
      } else {
        i++;
      }
    }
    return i;
  }

  /// The literal whose opening quote is at [i]; returns the index past it.
  int string(int i, {required bool raw}) {
    final start = i;
    final q = s[i];
    final close = s.startsWith(q * 3, i) ? q * 3 : q;
    i += close.length;
    final text = StringBuffer();
    while (i < s.length) {
      if (s.startsWith(close, i)) {
        onString?.call(start, text.toString());
        return i + close.length;
      }
      final c = s[i];
      if (close.length == 1 && c == '\n') break; // unterminated
      if (!raw && c == r'\') {
        text.write(s.substring(i, min(i + 2, s.length)));
        i += 2;
        continue;
      }
      if (!raw && c == r'$' && i + 1 < s.length) {
        if (s[i + 1] == '{') {
          text.write('\u0000');
          i = code(i + 2, interpolation: true);
          continue;
        }
        if (_identStart(s[i + 1])) {
          text.write('\u0000');
          i++;
          while (i < s.length && _ident(s[i])) {
            i++;
          }
          continue;
        }
      }
      text.write(c);
      i++;
    }
    onString?.call(start, text.toString());
    return i;
  }
}
