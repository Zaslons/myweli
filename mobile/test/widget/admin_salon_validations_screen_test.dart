import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/screens/admin/admin_salon_validation_detail_screen.dart';
import 'package:myweli/screens/admin/widgets/admin_segmented_control.dart';
import 'package:myweli/widgets/common/app_skeleton.dart';

import '../support/admin_console.dart';
import '../support/admin_salon_validation_fixtures.dart';
import '../support/fonts.dart';

/// « Salons à valider » — the queue, the sidebar's count and the dashboard's
/// card (B0.18 — docs/design/salon-go-live-approval.md §4.1, §4.2, §8.2),
/// on the server that ships them and on today's, which predates them (§9.2:
/// the console goes live first).
void main() {
  setUpAll(loadRealFonts);

  const queuePath = '/admin/salon-validations';

  group('the queue — four states', () {
    testWidgets('loading: the table’s skeleton while the tab is read', (
      t,
    ) async {
      final server = FakeAdminServer();
      final gate = Completer<void>();
      server.hold(queuePath, gate.future);
      await pumpConsole(t, server, location: queuePath, settle: false);
      await t.pump();
      await t.pump();
      expect(find.byType(AppSkeleton), findsOneWidget);
      expect(find.text('Beauté Divine'), findsNothing);
      gate.complete();
      await t.pumpAndSettle();
      expect(find.text('Beauté Divine'), findsOneWidget);
    });

    testWidgets('the list: every column of §4.2, in the market’s words', (
      t,
    ) async {
      final server = FakeAdminServer();
      // Not 3: the sidebar's badge would read the same figure.
      server.count = jsonResponse(queuePage(total: 9));
      server.queue['pending'] = jsonResponse(
        queuePage(
          total: 2,
          items: [
            queueItem(),
            {
              ...queueItem(id: 'provider_2', name: 'Chez Fatou'),
              'commune': null,
              'city': 'Dakar',
              'countryCode': 'SN',
              'ownerContact': null,
              'kycDocCount': 3,
            },
          ],
        ),
      );
      await pumpConsole(t, server, location: queuePath);

      for (final header in [
        'Salon',
        'Commune, ville',
        'Pays',
        'Demandé le',
        'Propriétaire (e-mail ou téléphone)',
        'Documents KYC',
      ]) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      expect(find.text('Beauté Divine'), findsOneWidget);
      expect(find.text('Cocody, Abidjan'), findsOneWidget);
      expect(find.text('CI'), findsOneWidget);
      // 2026-11-12T09:00Z, in Abidjan's time, breakable between words.
      expect(find.text('12 nov. 2026'), findsNWidgets(2));
      expect(find.text('awa@example.com'), findsOneWidget);
      expect(find.text('aucun'), findsOneWidget, reason: '0 documents');
      // The second row: no commune, Senegal, no owner, three documents.
      expect(find.text('Dakar'), findsOneWidget);
      expect(find.text('SN'), findsOneWidget);
      expect(find.text('sans propriétaire'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2 demandes'), findsOneWidget, reason: 'the pager');
      expect(find.text('Page 1'), findsOneWidget);
    });

    testWidgets('empty « En attente »: « Aucun salon en attente. »', (t) async {
      final server = FakeAdminServer();
      server.queue['pending'] = jsonResponse(queuePage(items: [], total: 0));
      await pumpConsole(t, server, location: queuePath);
      expect(find.text('Aucun salon en attente.'), findsOneWidget);
      expect(
        find.text('Les nouvelles demandes de mise en ligne arriveront ici.'),
        findsOneWidget,
      );
      expect(find.text('Page 1'), findsNothing, reason: 'no pager when empty');
    });

    testWidgets('error: « Chargement impossible », its sentence, and '
        '« Réessayer » that reads again', (t) async {
      final server = FakeAdminServer();
      server.queue['pending'] = jsonResponse({'error': 'internal_error'}, 500);
      await pumpConsole(t, server, location: queuePath);
      expect(find.text('Chargement impossible'), findsOneWidget);
      expect(find.text('Une erreur est survenue.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      server.queue['pending'] = jsonResponse(queuePage());
      await t.tap(find.text('Réessayer'));
      await t.pumpAndSettle();
      expect(find.text('Beauté Divine'), findsOneWidget);
      expect(find.text('Chargement impossible'), findsNothing);
    });
  });

  group('the tabs', () {
    testWidgets('« Refusés » and « Validés » read their own state, sorted '
        'by the decision, dated by it, each with its own empty state', (
      t,
    ) async {
      final server = FakeAdminServer();
      await pumpConsole(t, server, location: queuePath);
      expect(find.byType(AdminSegmentedControl), findsOneWidget);
      for (final label in ['En attente', 'Refusés', 'Validés']) {
        expect(find.text(label), findsOneWidget);
      }

      await t.tap(find.text('Refusés'));
      await t.pumpAndSettle();
      expect(
        server.to(queuePath).last.url.queryParameters,
        containsPair('state', 'refused'),
      );
      expect(server.to(queuePath).last.url.queryParameters['page'], '1');
      expect(server.to(queuePath).last.url.queryParameters['pageSize'], '50');
      expect(find.text('Refusé le'), findsOneWidget);
      expect(find.text('Aucun salon refusé.'), findsOneWidget);

      await t.tap(find.text('Validés'));
      await t.pumpAndSettle();
      expect(
        server.to(queuePath).last.url.queryParameters,
        containsPair('state', 'approved'),
      );
      expect(find.text('Validé le'), findsOneWidget);
      expect(find.text('Aucun salon validé.'), findsOneWidget);
    });

    testWidgets('« Validés » marks a validation still to finish, and a '
        'suspended salon, in words', (t) async {
      final server = FakeAdminServer();
      server.queue['approved'] = jsonResponse(
        queuePage(
          total: 2,
          items: [
            queueItem(state: 'approved'),
            {
              ...queueItem(
                id: 'provider_3',
                name: 'Barber Kings',
                state: 'approved',
                wentLive: true,
              ),
              'salonStatus': 'suspended',
            },
          ],
        ),
      );
      final p = await pumpConsole(t, server, location: queuePath);
      await t.tap(find.text('Validés'));
      await t.pumpAndSettle();
      expect(p.queue.items, hasLength(2));
      expect(find.text('Validation à terminer'), findsOneWidget);
      expect(find.text('Suspendu'), findsOneWidget);
    });

    testWidgets('50 per page: « Suivant » reads page 2, « Précédent » page 1', (
      t,
    ) async {
      final server = FakeAdminServer();
      server.queue['pending'] = jsonResponse(queuePage(total: 120));
      final p = await pumpConsole(t, server, location: queuePath);
      expect(find.text('120 demandes'), findsOneWidget);
      await t.tap(find.byTooltip('Suivant'));
      await t.pumpAndSettle();
      expect(server.to(queuePath).last.url.queryParameters['page'], '2');
      expect(p.queue.page, 2);
      expect(find.text('Page 2'), findsOneWidget);
      await t.tap(find.byTooltip('Précédent'));
      await t.pumpAndSettle();
      expect(server.to(queuePath).last.url.queryParameters['page'], '1');
    });

    testWidgets('an empty page past the first keeps « Précédent » — the way '
        'out is never hidden', (t) async {
      final server = FakeAdminServer();
      server.queue['pending'] = jsonResponse(queuePage(total: 51));
      final p = await pumpConsole(t, server, location: queuePath);
      // Page 2's one request was decided between the total and the rows.
      server.queue['pending'] = jsonResponse(
        queuePage(total: 51, page: 2, items: []),
      );
      await t.tap(find.byTooltip('Suivant'));
      await t.pumpAndSettle();
      expect(p.queue.page, 2);
      expect(find.text('Aucun salon en attente.'), findsOneWidget);
      expect(
        t
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_left),
            )
            .onPressed,
        isNotNull,
      );
      server.queue['pending'] = jsonResponse(queuePage(total: 51));
      await t.tap(find.byTooltip('Précédent'));
      await t.pumpAndSettle();
      expect(p.queue.page, 1);
      expect(find.text('Beauté Divine'), findsOneWidget);
    });

    testWidgets('« Suivant » by keyboard keeps the focus while the next page '
        'loads, and after (§13.5)', (t) async {
      final server = FakeAdminServer();
      server.queue['pending'] = jsonResponse(queuePage(total: 120));
      await pumpConsole(t, server, location: queuePath);
      final next = Focus.of(t.element(find.byIcon(Icons.chevron_right)));
      next.requestFocus();
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(next));

      final gate = Completer<void>();
      server.hold(queuePath, gate.future);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(server.to(queuePath).last.url.queryParameters['page'], '2');
      expect(find.byTooltip('Suivant'), findsOneWidget, reason: 'kept');
      expect(FocusManager.instance.primaryFocus, same(next));

      gate.complete();
      await t.pumpAndSettle();
      expect(find.text('Page 2'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, same(next));
    });
  });

  testWidgets('a row opens the request — the path the admin e-mail links to', (
    t,
  ) async {
    final server = FakeAdminServer();
    await pumpConsole(t, server, location: queuePath);
    await t.tap(find.text('Beauté Divine'));
    await t.pumpAndSettle();
    expect(find.byType(AdminSalonValidationDetailScreen), findsOneWidget);
    expect(
      server.to('/admin/salons/provider_1/validation'),
      hasLength(1),
      reason: 'the detail of the row tapped',
    );
  });

  group('before the backend deploy (§9.2)', () {
    testWidgets('the queue is a calm, explicit state — not an error, no '
        'tabs, no « Réessayer »', (t) async {
      final server = FakeAdminServer(oldBackend: true);
      await pumpConsole(t, server, location: queuePath);
      expect(
        find.text('Validation des salons pas encore active'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Le serveur ne gère pas encore la validation des salons. Cette '
          'page s’activera après sa mise à jour.',
        ),
        findsOneWidget,
      );
      expect(find.text('Chargement impossible'), findsNothing);
      expect(find.text('Réessayer'), findsNothing);
      expect(find.byType(AdminSegmentedControl), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      // CONTROL — it did ask, and was told the route does not exist.
      expect(server.to(queuePath), isNotEmpty);
    });

    testWidgets('…and the sidebar shows no count at all', (t) async {
      final server = FakeAdminServer(oldBackend: true);
      final p = await pumpConsole(t, server, location: queuePath);
      expect(p.count.count, isNull);
      expect(find.text('Salons à valider'), findsNWidgets(2));
      expect(_badge(), findsNothing);
    });
  });

  group('the sidebar’s count (§4.1)', () {
    testWidgets('« Salons à valider » under « Modération », with the count '
        'read with one row, said in words to a screen reader', (t) async {
      final handle = t.ensureSemantics();
      final server = FakeAdminServer();
      final p = await pumpConsole(t, server, location: queuePath);
      expect(p.count.count, 3);
      final count = server.requests.where(
        (r) => r.url.queryParameters['pageSize'] == '1',
      );
      expect(count.last.url.queryParameters['state'], 'pending');

      expect(_badge(), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(r'Salons à valider\n3 demandes en attente'),
        ),
        findsOneWidget,
      );
      // Under « Modération », before KYC.
      final moderation = t.getTopLeft(find.text('Modération')).dy;
      final entry = t.getTopLeft(find.text('Salons à valider').first).dy;
      final kyc = t.getTopLeft(find.text('KYC')).dy;
      expect(entry, greaterThan(moderation));
      expect(entry, lessThan(kyc));
      handle.dispose();
    });

    testWidgets('every entry is a ≥ 48dp target, measured — the tap-target '
        'guideline cannot see the sidebar', (t) async {
      // `androidTapTargetGuideline` skips a node touching the edge of a
      // scrollable or of the view (flutter_test accessibility.dart,
      // `_isAtBoundary`), and every sidebar entry starts at x = 0 inside its
      // ListView: a 44dp entry passes it. So the floor is measured here.
      await pumpConsole(t, FakeAdminServer(), location: queuePath);
      for (final label in [
        'Vue d’ensemble',
        'KYC',
        'Avis',
        'Salons',
        'Clients',
        'Litiges',
        'Journal',
        'Versions client',
      ]) {
        final tile = find
            .ancestor(
              of: find.text(label).first,
              matching: find.byType(InkWell),
            )
            .first;
        expect(t.getSize(tile).height, greaterThanOrEqualTo(48), reason: label);
      }
      final entry = find
          .ancestor(
            of: find.text('Salons à valider').first,
            matching: find.byType(InkWell),
          )
          .first;
      expect(t.getSize(entry).height, greaterThanOrEqualTo(48));
    });

    testWidgets('no badge without the provider — a console, or a test, '
        'built without it still renders its sidebar', (t) async {
      final server = FakeAdminServer();
      await pumpConsole(t, server, location: queuePath, withCount: false);
      expect(t.takeException(), isNull);
      expect(find.text('Salons à valider'), findsNWidgets(2));
      expect(_badge(), findsNothing);
    });

    testWidgets('no badge when the count fails', (t) async {
      final server = FakeAdminServer();
      server.count = jsonResponse({'error': 'internal_error'}, 500);
      final p = await pumpConsole(t, server, location: queuePath);
      expect(p.count.count, isNull);
      expect(_badge(), findsNothing);
    });

    testWidgets('no badge when nobody is waiting', (t) async {
      final server = FakeAdminServer();
      server.count = jsonResponse(queuePage(items: [], total: 0));
      final p = await pumpConsole(t, server, location: queuePath);
      expect(p.count.count, 0);
      expect(_badge(), findsNothing);
    });
  });

  group('the dashboard (§4.1)', () {
    testWidgets('« Salons à valider » is a card with the overview’s count, '
        'and it opens the queue', (t) async {
      final server = FakeAdminServer();
      await pumpConsole(t, server, location: '/admin/dashboard');
      final card = find.ancestor(
        of: find.text('Salons à valider').last,
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: card.first, matching: find.text('3')),
        findsOneWidget,
      );
      await t.tap(find.text('Salons à valider').last);
      await t.pumpAndSettle();
      expect(server.to(queuePath), isNotEmpty);
      expect(find.text('Aucun salon en attente.'), findsNothing);
      expect(find.text('Beauté Divine'), findsOneWidget);
    });

    testWidgets('on today’s server the overview has no such key: no card, '
        'never « 0 »', (t) async {
      final server = FakeAdminServer(oldBackend: true);
      await pumpConsole(t, server, location: '/admin/dashboard');
      expect(find.text('KYC en attente'), findsOneWidget, reason: 'C');
      // Only the sidebar's entry: the card is absent.
      expect(find.text('Salons à valider'), findsOneWidget);
    });
  });
}

/// The count pill — a [Text] whose semantics are « N demandes en attente ».
Finder _badge() => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.semanticsLabel ?? '').contains('en attente') &&
      RegExp(r'^\d+$').hasMatch(w.data ?? ''),
);
