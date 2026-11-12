import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/admin_console.dart';
import '../support/admin_salon_validation_fixtures.dart';
import '../support/fonts.dart';
import '_a11y.dart';

/// « Salons à valider » at the console's widths and at 200 % text (B0.18 —
/// docs/design/salon-go-live-approval.md §4; SYSTEM.md §10, §13.2, §13.3).
///
/// The console lives at `expanded` (≥ 840dp, SYSTEM.md §10) beside a fixed
/// 240dp sidebar, so its two points are that floor and a desktop window, at
/// 1× and at 2×. Each configuration is its own `testWidgets` — the overflow
/// report latches once per render object (`layout_test.dart`, « Why the
/// loops are outside `testWidgets` »), and a loop inside one test measures
/// the first width only.
///
/// Per configuration, the repo's own gate:
///  **A** nothing overflowed — `takeException()`;
///  **B** no text cut off without saying so — [expectNoUndeclaredTruncation];
///  **D** no text clipped by a fixed height — [expectNoVerticalClip];
///  **C** the subject actually rendered — a string only it draws. Without C,
///  a subject that landed on another state would measure its padding green.
void main() {
  setUpAll(loadRealFonts);

  const queue = '/admin/salon-validations';
  const request = '/admin/salon-validations/provider_1';

  /// A long name, a long e-mail and a long city: what wraps first.
  Map<String, dynamic> longRow() => {
    ...queueItem(
      id: 'provider_2',
      name: 'Institut de beauté et de bien-être Les Jardins de Cocody',
    ),
    'commune': 'Yopougon-Attié',
    'city': 'Abidjan',
    'ownerContact': 'aminata.kouassi-traore.institut@example-salon.ci',
    'kycDocCount': 12,
  };

  final subjects =
      <
        String,
        ({
          String location,
          String c,
          FakeAdminServer Function() server,
          Future<void> Function(WidgetTester t)? then,
        })
      >{
        'the queue, listed': (
          location: queue,
          c: 'Les Jardins de Cocody',
          server: () => FakeAdminServer()
            ..queue['pending'] = jsonResponse(
              queuePage(total: 120, items: [queueItem(), longRow()]),
            ),
          then: null,
        ),
        'the queue, empty': (
          location: queue,
          c: 'Aucun salon en attente.',
          server: () => FakeAdminServer()
            ..queue['pending'] = jsonResponse(queuePage(items: [], total: 0)),
          then: null,
        ),
        'the queue, failed': (
          location: queue,
          c: 'Chargement impossible',
          server: () => FakeAdminServer()
            ..queue['pending'] = jsonResponse({'error': 'internal_error'}, 500),
          then: null,
        ),
        'the queue, before the backend deploy': (
          location: queue,
          c: 'Validation des salons pas encore active',
          server: () => FakeAdminServer(oldBackend: true),
          then: null,
        ),
        'the request, pending': (
          location: request,
          c: 'Ouvrir dans OpenStreetMap',
          server: FakeAdminServer.new,
          then: null,
        ),
        'the request, suspended, with a 409 in the bar': (
          location: request,
          c: 'Salon suspendu : levez d’abord la suspension.',
          server: () => FakeAdminServer()
            ..detail['provider_1'] = jsonResponse(
              detailJson(salonStatus: 'suspended'),
            ),
          then: null,
        ),
        'the request, to finish, after an incomplete 409': (
          location: request,
          c: 'Le salon n’est plus complet : photos, horaires.',
          server: () => FakeAdminServer()
            ..detail['provider_1'] = jsonResponse(
              detailJson(
                validation: validationJson(
                  state: 'approved',
                  decidedAt: '2026-11-12T10:00:00.000Z',
                ),
              ),
            )
            ..approve = jsonResponse({
              'error': 'incomplete',
              'missing': ['photos', 'availability', 'offer'],
            }, 409),
          then: (t) async {
            await t.tap(find.text('Valider la mise en ligne'));
            await t.pumpAndSettle();
          },
        ),
        'the request, failed': (
          location: request,
          c: 'Chargement impossible',
          server: () => FakeAdminServer()
            ..detail['provider_1'] = jsonResponse({
              'error': 'internal_error',
            }, 500),
          then: null,
        ),
        'the request, not found': (
          location: request,
          c: 'Demande introuvable',
          server: () => FakeAdminServer()..detail.clear(),
          then: null,
        ),
        'the request, before the backend deploy': (
          location: request,
          c: 'Validation des salons pas encore active',
          server: () => FakeAdminServer(oldBackend: true),
          then: null,
        ),
        'the refusal dialog, its errors shown': (
          location: request,
          c: 'Une note est obligatoire pour le motif « Autre ».',
          server: FakeAdminServer.new,
          then: (t) async {
            await t.tap(find.text('Refuser'));
            await t.pumpAndSettle();
            await t.ensureVisible(find.text('Autre'));
            await t.tap(find.text('Autre'));
            await t.tap(find.widgetWithText(TextButton, 'Refuser'));
            await t.pumpAndSettle();
          },
        ),
        'the dashboard': (
          location: '/admin/dashboard',
          c: 'KYC en attente',
          server: FakeAdminServer.new,
          then: null,
        ),
        'a salon’s page, « Lever la suspension »': (
          location: '/admin/providers/provider_9',
          c: 'Lever la suspension',
          server: FakeAdminServer.new,
          then: null,
        ),
        'the salons list, « Lever la suspension »': (
          location: '/admin/providers',
          c: 'Lever la suspension',
          server: FakeAdminServer.new,
          then: null,
        ),
      };

  for (final MapEntry(key: name, value: s) in subjects.entries) {
    for (final size in [kConsoleNarrow, kConsoleWide]) {
      for (final scale in [1.0, 2.0]) {
        final at = '${size.width.toInt()}dp × $scale×';
        testWidgets('$name — whole at $at', (t) async {
          await pumpConsole(
            t,
            s.server(),
            location: s.location,
            size: size,
            scale: scale,
          );
          await s.then?.call(t);
          expect(t.takeException(), isNull, reason: 'A at $at');
          expectNoUndeclaredTruncation(t, context: '$name at $at');
          expectNoVerticalClip(t, context: '$name at $at');
          expect(
            find.textContaining(s.c),
            findsWidgets,
            reason: 'C: « ${s.c} »',
          );
        });
      }
    }
  }

  testWidgets('the loading states are whole at 840dp × 2×', (t) async {
    final server = FakeAdminServer();
    server.hold(queue, Completer<void>().future);
    await pumpConsole(
      t,
      server,
      location: queue,
      size: kConsoleNarrow,
      scale: 2,
      settle: false,
    );
    await t.pump();
    await t.pump();
    expect(t.takeException(), isNull);
  });

  group('the queue’s columns', () {
    testWidgets('six on a desktop window, at 2× too', (t) async {
      await pumpConsole(
        t,
        FakeAdminServer(),
        location: queue,
        size: kConsoleWide,
        scale: 2,
      );
      expect(find.text('Documents KYC'), findsOneWidget);
      expect(find.text('Pays'), findsOneWidget);
    });

    testWidgets('one stacked column when they cannot hold their words: '
        '840dp × 2× — every fact still there, each with its label', (t) async {
      await pumpConsole(
        t,
        FakeAdminServer(),
        location: queue,
        size: kConsoleNarrow,
        scale: 2,
      );
      expect(find.text('Propriétaire (e-mail ou téléphone)'), findsNothing);
      for (final label in [
        'Commune, ville',
        'Pays',
        'Demandé le',
        'Propriétaire',
        'Documents KYC',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final value in ['Cocody, Abidjan', 'CI', '12 nov. 2026', 'aucun']) {
        expect(find.text(value), findsOneWidget, reason: value);
        expectNoMidWordBreak(t, value, '840dp × 2×');
      }
    });
  });

  group('the request’s two columns', () {
    testWidgets('side by side on a desktop window', (t) async {
      await pumpConsole(
        t,
        FakeAdminServer(),
        location: request,
        size: kConsoleWide,
      );
      final salon = t.getTopLeft(find.text('Photos'));
      final owner = t.getTopLeft(find.text('Propriétaire'));
      expect(owner.dx, greaterThan(salon.dx), reason: 'the owner on the right');
      expect(owner.dy, lessThan(salon.dy), reason: 'beside the salon’s top');
    });

    for (final (size, scale) in [(kConsoleNarrow, 1.0), (kConsoleWide, 2.0)]) {
      testWidgets('stacked at ${size.width.toInt()}dp × $scale× — the owner '
          'under the salon, full width', (t) async {
        await pumpConsole(
          t,
          FakeAdminServer(),
          location: request,
          size: size,
          scale: scale,
        );
        final salon = t.getTopLeft(find.text('Photos'));
        final owner = t.getTopLeft(find.text('Propriétaire'));
        expect(owner.dx, salon.dx);
        expect(owner.dy, greaterThan(salon.dy));
      });
    }
  });

  group('tap targets ≥ 48 × 48, each labelled (§13.2, §13.4)', () {
    for (final (name, location, then)
        in <(String, String, Future<void> Function(WidgetTester)?)>[
          ('the queue', queue, null),
          ('the request', request, null),
          (
            'the refusal dialog',
            request,
            (t) async {
              await t.tap(find.text('Refuser'));
              await t.pumpAndSettle();
            },
          ),
        ]) {
      testWidgets(name, (t) async {
        final handle = t.ensureSemantics();
        await pumpConsole(t, FakeAdminServer(), location: location);
        await then?.call(t);
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });

      // Where the console runs: a desktop browser, whose OS Flutter Web
      // reports as the platform — compact density and shrink-wrapped targets
      // by default, which `flutter test` (Android) never renders.
      for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
        testWidgets('$name — on ${platform.name}, as in a desktop browser', (
          t,
        ) async {
          final handle = t.ensureSemantics();
          debugDefaultTargetPlatformOverride = platform;
          try {
            await pumpConsole(t, FakeAdminServer(), location: location);
            await then?.call(t);
            await expectLater(t, meetsGuideline(androidTapTargetGuideline));
            await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
          handle.dispose();
        });
      }
    }
  });
}
