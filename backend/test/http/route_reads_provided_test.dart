import 'dart:io';

import 'package:test/test.dart';

/// **Every `context.read<T>()` in the route tree has a `provider<T>` in
/// `routes/_middleware.dart`.**
///
/// A handler test builds its own context and answers every `read` it is
/// asked for, so it passes whether or not the composition root provides the
/// type. In the running server a missing provider is a `StateError` on the
/// first request — a 500 on that route and nowhere else. B0.18's admin
/// routes read a service no route read before (`SalonValidationService`):
/// every handler test green, every one of those routes a 500 in production.
///
/// Walks the whole route tree with no exemptions, like
/// `no_body_cast_in_routes_test.dart`. The patterns are declared once, so
/// the proof below exercises the objects the scan runs.
final readPattern = RegExp(r'\bread<(\w+)>\(\)');
final providerPattern = RegExp(r'\bprovider<(\w+)>\(');

/// Comments stripped first: a comment quoting a `read<T>()` is no read.
String stripComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  List<File> routeFiles() => Directory('routes')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  Set<String> provided() => {
    for (final f in routeFiles())
      if (f.path.endsWith('_middleware.dart'))
        for (final m in providerPattern.allMatches(
          stripComments(f.readAsStringSync()),
        ))
          m.group(1)!,
  };

  test('the scan is not vacuous: routes read, and the root provides', () {
    final reads = [
      for (final f in routeFiles())
        ...readPattern.allMatches(stripComments(f.readAsStringSync())),
    ];
    expect(reads.length, greaterThan(50));
    expect(provided(), containsAll(['TokenService', 'AnalyticsService']));
  });

  test('every type a route reads is provided by a middleware', () {
    final have = provided();
    final offenders = <String>[];
    for (final file in routeFiles()) {
      final source = stripComments(file.readAsStringSync());
      for (final m in readPattern.allMatches(source)) {
        if (!have.contains(m.group(1))) {
          offenders.add('${file.path}: read<${m.group(1)}>()');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a route reads a type no middleware provides: in the running '
          'server that is a 500 on its first request. Add '
          '`.use(provider<T>((_) => …))` to routes/_middleware.dart.',
    );
  });

  test('the patterns match what they must, and not a comment', () {
    for (final line in [
      'context.read<SalonValidationService>().queue(',
      'await context\n      .read<SalonProvisioningService>()\n',
    ]) {
      expect(readPattern.hasMatch(line), isTrue, reason: line);
    }
    expect(
      providerPattern.hasMatch(
        '.use(provider<SalonValidationService>((_) => salonValidationService))',
      ),
      isTrue,
    );
    expect(
      readPattern.hasMatch(stripComments('// context.read<Ghost>()')),
      isFalse,
    );
  });
}
