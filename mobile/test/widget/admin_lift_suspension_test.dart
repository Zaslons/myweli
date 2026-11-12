import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/screens/admin/widgets/audit_actions.dart';

import '../support/admin_console.dart';
import '../support/fonts.dart';

/// « Réactiver » becomes « Lever la suspension » (B0.18 —
/// docs/design/salon-go-live-approval.md §4.4, §8.2): a lift no longer always
/// puts the salon back online, so its snackbar says where the salon went —
/// one sentence per reason — on the salons list and on a salon's page, from
/// the server that ships B0.18 AND from today's, which answers the whole
/// salon written `active` (§9.2: the console goes live first).
void main() {
  setUpAll(loadRealFonts);

  const offline = 'Suspension levée — le salon reste hors ligne : ';
  final cases = <(String, String?, String)>[
    ('active', null, 'Salon remis en ligne'),
    ('draft', 'not_validated', '${offline}non validé'),
    ('draft', 'offer_not_live', '${offline}offre inactive'),
    ('draft', 'unpaid', '${offline}dépublié pour impayé'),
    ('draft', 'no_owner', '${offline}sans propriétaire'),
    ('draft', 'unknown_prior', '$offlineétat antérieur inconnu'),
  ];

  for (final (where, location) in [
    ('the salons list', '/admin/providers'),
    ('a salon’s page', '/admin/providers/provider_9'),
  ]) {
    group(where, () {
      testWidgets('the button reads « Lever la suspension », never '
          '« Réactiver »', (t) async {
        await pumpConsole(t, FakeAdminServer(), location: location);
        expect(find.text('Lever la suspension'), findsOneWidget);
        expect(find.text('Réactiver'), findsNothing);
      });

      for (final (status, reason, sentence) in cases) {
        testWidgets('$status${reason == null ? '' : ' ($reason)'} → '
            '« $sentence »', (t) async {
          final server = FakeAdminServer()
            ..restore = jsonResponse({'status': status, 'reason': reason});
          final p = await pumpConsole(t, server, location: location);
          await t.tap(find.text('Lever la suspension'));
          await t.pump();
          await t.pump();
          expect(find.text(sentence), findsOneWidget);
          final bar = t.widget<SnackBar>(find.byType(SnackBar));
          // Back online is a success; lifted-but-offline is not an error.
          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.byIcon(
                status == 'active'
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
              ),
            ),
            findsOneWidget,
          );
          expect(bar.content, isNotNull);
          // The B0.18 answer is not a salon: only its status enters the row.
          final row = location == '/admin/providers'
              ? p.providers.items.singleWhere((r) => r['id'] == 'provider_9')
              : p.providerDetail.provider!;
          expect(row['status'], status);
          expect(row.containsKey('reason'), isFalse);
          await t.pumpAndSettle();
        });
      }

      testWidgets('an unknown reason from a newer server is still a '
          'sentence, never the wire value', (t) async {
        final server = FakeAdminServer()
          ..restore = jsonResponse({'status': 'draft', 'reason': 'brand_new'});
        await pumpConsole(t, server, location: location);
        await t.tap(find.text('Lever la suspension'));
        await t.pump();
        await t.pump();
        expect(find.text('${offline}motif non reconnu'), findsOneWidget);
        expect(find.textContaining('brand_new'), findsNothing);
        await t.pumpAndSettle();
      });

      testWidgets('today’s server answers the whole salon, written active: '
          '« Salon remis en ligne »', (t) async {
        final server = FakeAdminServer(oldBackend: true);
        await pumpConsole(t, server, location: location);
        await t.tap(find.text('Lever la suspension'));
        await t.pump();
        await t.pump();
        expect(find.text('Salon remis en ligne'), findsOneWidget);
        expect(server.to('/admin/providers/provider_9/restore'), hasLength(1));
        await t.pumpAndSettle();
      });

      testWidgets('not suspended any more (409): its sentence, as an error', (
        t,
      ) async {
        final server = FakeAdminServer()
          ..restore = jsonResponse({'error': 'not_suspended'}, 409);
        await pumpConsole(t, server, location: location);
        await t.tap(find.text('Lever la suspension'));
        await t.pump();
        await t.pump();
        expect(find.text('Ce salon n’est pas suspendu.'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
        );
        await t.pumpAndSettle();
      });
    });
  }

  test('the audit log says « Suspension levée », and names the decisions', () {
    expect(auditActionLabel('provider.restore'), 'Suspension levée');
    expect(auditActionLabel('salon.approve'), 'Salon validé');
    expect(auditActionLabel('salon.refuse'), 'Mise en ligne refusée');
  });
}
