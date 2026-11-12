import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/dart_source.dart';

/// The admin console draws every image from another origin through
/// `AdminRemoteImage`, and nothing else.
///
/// ## Why
///
/// The console is Flutter Web on CanvasKit, served from `admin.myweli.com`.
/// Every other way of drawing a network image there (`TimedCachedImage`,
/// cached_network_image, a bare `Image.network` or `NetworkImage`, an
/// `SvgPicture.network`) reads the bytes through `<img crossorigin>` or
/// `fetch`, which needs `Access-Control-Allow-Origin` for the console's
/// origin. R2 sends none: probed 2026-11-12, `admin.myweli.com` is on no
/// bucket's list (the private buckets allow only a PUT, from `myweli.com` and
/// `www`; the public one GET and PUT from `myweli.com`;
/// docs/design/admin-remote-images.md §1). Each such image would show the
/// « image not available » icon, on the console only, and no test on the VM
/// can see it.
///
/// ## What it walks, and what it cannot see
///
/// The import graph from `lib/main_admin.dart`, not a list of screens, so a
/// new admin screen, or a shared widget an admin screen starts to use, is in
/// scope the day it is imported. Comments are stripped with the shared scanner.
///
/// It cannot see an image drawn by a package (outside `lib/`) from a URL we
/// pass it, nor a URL that reaches `Image(image: …)` through a provider built
/// in a file the console does not import. Neither exists today.
void main() {
  final root = Directory.current.path.endsWith('mobile') ? '' : 'mobile/';
  final lib = '${root}lib';
  const widget = 'screens/admin/widgets/admin_remote_image.dart';

  /// Files reachable from the console's entrypoint, relative to `lib/`.
  Set<String> reachable() {
    final directive = RegExp(
      r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]'''
      r'''((?:\s+if\s*\([^)]*\)\s*['"][^'"]+['"])*)''',
      multiLine: true,
    );
    final conditional = RegExp(r'''if\s*\([^)]*\)\s*['"]([^'"]+)['"]''');
    final part = RegExp(r'''^\s*part\s+['"]([^'"]+)['"]''', multiLine: true);
    final seen = <String>{};
    final stack = <String>['main_admin.dart'];
    while (stack.isNotEmpty) {
      final rel = stack.removeLast();
      if (!seen.add(rel)) continue;
      final file = File('$lib/$rel');
      expect(file.existsSync(), isTrue, reason: 'unresolved import: $rel');
      final source = stripDartComments(file.readAsStringSync());
      final targets = <String>[
        for (final m in directive.allMatches(source)) ...[
          m.group(1)!,
          for (final c in conditional.allMatches(m.group(2)!)) c.group(1)!,
        ],
        for (final m in part.allMatches(source)) m.group(1)!,
      ];
      for (final target in targets) {
        if (target.startsWith('dart:')) continue;
        if (target.startsWith('package:')) {
          if (!target.startsWith('package:myweli/')) continue;
          stack.add(target.substring('package:myweli/'.length));
          continue;
        }
        final dir = File(rel).parent.path;
        stack.add(
          Uri.parse(
            '$dir/$target',
          ).normalizePath().path.replaceFirst(RegExp(r'^\./'), ''),
        );
      }
    }
    return seen;
  }

  /// What reads a remote image's bytes, or brings in something that does.
  final forbidden = <String, RegExp>{
    'TimedCachedImage': RegExp(r'\bTimedCachedImage\b'),
    'cached_network_image': RegExp(
      r'\bCachedNetworkImage\w*|package:cached_network_image/',
    ),
    'Image.network': RegExp(r'\bImage\s*\.\s*network\s*\('),
    'NetworkImage': RegExp(r'\bNetworkImage\s*\('),
    'SvgPicture.network': RegExp(r'\bSvgPicture\s*\.\s*network\s*\('),
  };

  test('the walk reaches the console, not an empty set', () {
    final files = reachable();
    // A walk that resolved nothing would pass everything below.
    expect(files.length, greaterThan(50));
    expect(
      files,
      containsAll(<String>[
        'core/router/admin_router.dart',
        'screens/admin/admin_kyc_detail_screen.dart',
        'screens/admin/admin_dispute_detail_screen.dart',
        'screens/admin/widgets/admin_detail_widgets.dart',
        // B0.18's salon photos, on the public bucket (spec §4).
        'screens/admin/admin_salon_validation_detail_screen.dart',
        widget,
      ]),
    );
  });

  test('no file the console imports draws a remote image another way', () {
    final offenders = <String>[];
    for (final rel in reachable().toList()..sort()) {
      if (rel == widget) continue;
      final code = stripDartComments(File('$lib/$rel').readAsStringSync());
      for (final e in forbidden.entries) {
        if (e.value.hasMatch(code)) offenders.add('$rel: ${e.key}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'R2 sends admin.myweli.com no CORS header: draw it with '
          'AdminRemoteImage (docs/design/admin-remote-images.md).',
    );
  });

  test('AdminRemoteImage asks for the <img>, and sends no header', () {
    final code = stripDartComments(File('$lib/$widget').readAsStringSync());
    expect(
      RegExp(
        r'webHtmlElementStrategy\s*:\s*WebHtmlElementStrategy\s*\.\s*prefer\b',
      ).hasMatch(code),
      isTrue,
    );
    // With any header the framework fetches the bytes: CORS again.
    expect(RegExp(r'\bheaders\s*:').hasMatch(code), isFalse);
  });
}
