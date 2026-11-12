import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/screens/admin/admin_salon_validation_detail_screen.dart';
import 'package:myweli/screens/admin/admin_salon_validations_screen.dart';
import 'package:myweli/widgets/common/app_button.dart';
import 'package:myweli/widgets/common/app_skeleton.dart';

import '../support/admin_console.dart';
import '../support/admin_salon_validation_fixtures.dart';
import '../support/fonts.dart';

/// One salon's request to go live, and the decision (B0.18 —
/// docs/design/salon-go-live-approval.md §4.3, §4.4, §8.2).
void main() {
  setUpAll(loadRealFonts);

  const path = '/admin/salon-validations/provider_1';
  const detailPath = '/admin/salons/provider_1/validation';

  Map<String, dynamic> detail({
    Map<String, dynamic>? validation,
    String salonStatus = 'draft',
    Map<String, dynamic> salon = const {},
    Map<String, dynamic>? owner,
    bool noOwner = false,
    List<Map<String, dynamic>>? events,
    bool neverAsked = false,
  }) {
    final base = detailJson(
      validation: validation,
      salonStatus: salonStatus,
      neverAsked: neverAsked,
    );
    return {
      ...base,
      'salon': {...base['salon'] as Map<String, dynamic>, ...salon},
      'owner': noOwner
          ? null
          : {...base['owner'] as Map<String, dynamic>, ...?owner},
      'events': events ?? base['events'],
    };
  }

  FakeAdminServer serving(Map<String, dynamic> body) =>
      FakeAdminServer()..detail['provider_1'] = jsonResponse(body);

  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );

  bool enabled(WidgetTester t, String label) =>
      t.widget<ButtonStyleButton>(button(label).first).enabled;

  group('four states', () {
    testWidgets('loading: a skeleton while the request is read', (t) async {
      final server = FakeAdminServer();
      final gate = Completer<void>();
      server.hold(detailPath, gate.future);
      await pumpConsole(t, server, location: path, settle: false);
      await t.pump();
      await t.pump();
      expect(find.byType(SkeletonDetail), findsOneWidget);
      expect(find.text('Beauté Divine'), findsNothing);
      gate.complete();
      await t.pumpAndSettle();
      expect(find.text('Beauté Divine'), _salonAndBusiness);
    });

    testWidgets('error: « Chargement impossible », the sentence, and a '
        '« Réessayer » that reads again', (t) async {
      final server = FakeAdminServer()
        ..detail['provider_1'] = jsonResponse({'error': 'internal_error'}, 500);
      await pumpConsole(t, server, location: path);
      expect(find.text('Chargement impossible'), findsOneWidget);
      expect(find.text('Une erreur est survenue.'), findsOneWidget);
      server.detail['provider_1'] = jsonResponse(detailJson());
      await t.tap(find.text('Réessayer'));
      await t.pumpAndSettle();
      expect(find.text('Beauté Divine'), _salonAndBusiness);
      expect(server.to(detailPath), hasLength(2));
    });

    testWidgets('a salon that does not exist: its own state, and a way back '
        'to the queue — never a « Réessayer » that cannot succeed', (t) async {
      final server = FakeAdminServer()..detail.clear();
      await pumpConsole(t, server, location: path);
      expect(find.text('Demande introuvable'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
      await t.tap(find.text('Voir les salons à valider'));
      await t.pumpAndSettle();
      expect(find.byType(AdminSalonValidationsScreen), findsOneWidget);
    });

    testWidgets('before the backend deploy (§9.2): the calm notice, not an '
        'error', (t) async {
      await pumpConsole(t, FakeAdminServer(oldBackend: true), location: path);
      expect(
        find.text('Validation des salons pas encore active'),
        findsOneWidget,
      );
      expect(find.text('Chargement impossible'), findsNothing);
      expect(find.text('Réessayer'), findsNothing);
      expect(find.byType(SkeletonDetail), findsNothing);
    });
  });

  testWidgets('B9.8 — the way to B never shows A: A’s salon, A’s owner and '
      'a bar acting on B’s id', (t) async {
    final server = FakeAdminServer()
      ..detail['provider_2'] = jsonResponse(
        detailJson(id: 'provider_2', name: 'Salon Ancien'),
      );
    final gate = Completer<void>();
    await pumpConsole(
      t,
      server,
      location: path,
      settle: false,
      before: (p) async {
        await p.detail.load(const SalonId('provider_2'));
        server.hold(detailPath, gate.future);
      },
    );
    // The FIRST frame — before this screen's own load has even started,
    // the provider still holds A whole.
    expect(find.text('Salon Ancien'), findsNothing);
    expect(find.text('Valider la mise en ligne'), findsNothing);
    expect(find.byType(SkeletonDetail), findsOneWidget);
    await t.pump();
    await t.pump();
    expect(find.text('Salon Ancien'), findsNothing);
    expect(find.text('Valider la mise en ligne'), findsNothing);
    expect(find.byType(SkeletonDetail), findsOneWidget);
    gate.complete();
    await t.pumpAndSettle();
    expect(find.text('Beauté Divine'), _salonAndBusiness);
    expect(find.text('Salon Ancien'), findsNothing);
  });

  group('the salon (left)', () {
    testWidgets('name, type, the request, the offer, services and prices, '
        'the hours', (t) async {
      await pumpConsole(
        t,
        serving(detail(salon: {'category': 'salon'})),
        location: path,
      );
      expect(find.text('Beauté Divine'), _salonAndBusiness);
      expect(find.text('Salon de coiffure'), findsOneWidget);
      expect(find.text('En attente de validation'), findsOneWidget);
      expect(find.text('Brouillon'), findsNWidgets(2), reason: 'and its twin');
      expect(
        find.text('Essai gratuit · Pro · jusqu’au 10 févr. 2027'),
        findsOneWidget,
      );
      expect(find.text('Tresses · 2h'), findsOneWidget);
      expect(find.text('15 000 – 25 000 FCFA'), findsOneWidget);
      expect(find.text('Brushing · 45 min · masqué'), findsOneWidget);
      expect(find.text('5 000 FCFA'), findsOneWidget);
      expect(find.text('Lundi'), findsOneWidget);
      expect(find.text('09:00 – 18:00'), findsOneWidget);
      // Tuesday is absent from the schedule, Sunday empty: both closed.
      expect(find.text('Fermé'), findsNWidgets(6));
    });

    testWidgets('the photos are <img> elements — the public bucket refuses '
        'admin.myweli.com a CORS fetch — with a placeholder when one fails', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await pumpConsole(t, serving(detail()), location: path);
      final images = t.widgetList<Image>(find.byType(Image)).toList();
      expect(images, hasLength(3));
      for (final image in images) {
        final provider = image.image as NetworkImage;
        expect(
          provider.webHtmlElementStrategy,
          WebHtmlElementStrategy.prefer,
          reason: provider.url,
        );
        expect(image.errorBuilder, isNotNull);
      }
      expect(
        (images.first.image as NetworkImage).url,
        'https://cdn.myweli.com/a.jpg',
      );
      // flutter_test answers every HTTP request 400: each photo fails, and
      // shows the tokenised placeholder, said in words.
      expect(find.byIcon(Icons.broken_image_outlined), findsNWidgets(3));
      expect(find.bySemanticsLabel('Photo indisponible'), findsNWidgets(3));
      expect(find.text('Photo 1'), findsOneWidget);
      expect(
        find.byTooltip('Ouvrir « Photo 3 » dans un nouvel onglet'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('no photo, no service, no hours: each says so', (t) async {
      await pumpConsole(
        t,
        serving(
          detail(
            salon: {
              'imageUrls': <String>[],
              'services': <Object>[],
              'availability': {'weeklySchedule': <String, Object>{}},
            },
          ),
        ),
        location: path,
      );
      expect(find.text('Aucune photo'), findsOneWidget);
      expect(find.text('Aucun service'), findsOneWidget);
      expect(find.text('Horaires non renseignés'), findsOneWidget);
    });

    testWidgets('the pin’s coordinates, and « Ouvrir dans OpenStreetMap » '
        'opens exactly that pin', (t) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final opened = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        opened.add('${call.method} ${(call.arguments as Map)['url']}');
        return true;
      });
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await pumpConsole(t, serving(detail()), location: path);
      expect(find.text('5.36000, -3.99000'), findsOneWidget);
      await t.ensureVisible(find.text('Ouvrir dans OpenStreetMap'));
      await t.tap(find.text('Ouvrir dans OpenStreetMap'));
      await t.pumpAndSettle();
      expect(opened, [
        'launch https://www.openstreetmap.org/?mlat=5.360000&mlon=-3.990000'
            '#map=17/5.360000/-3.990000',
      ]);
    });

    testWidgets('no pin: said in words, and no map to open', (t) async {
      await pumpConsole(
        t,
        serving(detail(salon: {'latitude': null, 'longitude': null})),
        location: path,
      );
      expect(find.text('Aucune position sur la carte'), findsOneWidget);
      expect(find.text('Ouvrir dans OpenStreetMap'), findsNothing);
    });

    testWidgets('the phone with its calling code — Abidjan’s grouped, '
        'Dakar’s as stored, a number without one said so', (t) async {
      await pumpConsole(t, serving(detail()), location: path);
      expect(find.text('+225 07 07 07 07 07'), findsNWidgets(2));
      expect(find.text('+225'), findsOneWidget);
    });

    testWidgets('…a Senegalese number reads +221', (t) async {
      await pumpConsole(
        t,
        serving(
          detail(salon: {'phoneNumber': '+221771234567', 'countryCode': 'SN'}),
        ),
        location: path,
      );
      expect(find.text('+221771234567'), findsOneWidget);
      expect(find.text('+221'), findsOneWidget);
      expect(find.text('SN'), findsOneWidget);
    });

    testWidgets('…and a number stored without one cannot say its country', (
      t,
    ) async {
      await pumpConsole(
        t,
        serving(detail(salon: {'phoneNumber': '0707070707'})),
        location: path,
      );
      expect(find.text('absent du numéro'), findsOneWidget);
    });
  });

  group('the owner (right)', () {
    testWidgets('name, contact, account age, « aucun document » with no '
        'KYC link, the other salons, the history', (t) async {
      await pumpConsole(t, serving(detail()), location: path);
      expect(find.text('Awa Koné'), findsOneWidget);
      expect(find.text('awa@example.com'), findsOneWidget);
      expect(find.text('12 jours · depuis le 31 oct. 2026'), findsOneWidget);
      expect(find.text('aucun document'), findsOneWidget);
      expect(find.text('Ouvrir le dossier KYC'), findsNothing);
      expect(find.text('Beauté Divine 2'), findsOneWidget);
      expect(find.text('Demande de mise en ligne'), findsNWidgets(2));
      expect(find.text('12 nov. 2026 à 09:00'), findsOneWidget);
    });

    testWidgets('« N documents · {status} », and its link to the KYC file', (
      t,
    ) async {
      await pumpConsole(
        t,
        serving(detail(owner: {'kycDocCount': 2, 'kycStatus': 'pending'})),
        location: path,
      );
      expect(find.text('2 documents · En attente'), findsOneWidget);
      await t.ensureVisible(find.text('Ouvrir le dossier KYC'));
      await t.tap(find.text('Ouvrir le dossier KYC'));
      await t.pumpAndSettle();
      expect(find.text('KYC acc_1'), findsOneWidget);
    });

    testWidgets('another salon opens that salon’s page', (t) async {
      final server = serving(detail());
      await pumpConsole(t, server, location: path);
      await t.ensureVisible(find.text('Beauté Divine 2'));
      await t.tap(find.text('Beauté Divine 2'));
      await t.pumpAndSettle();
      expect(server.to('/admin/providers/provider_2'), isNotEmpty);
    });

    testWidgets('no active owner: the server’s own sentence, before the '
        'button is pressed', (t) async {
      await pumpConsole(t, serving(detail(noOwner: true)), location: path);
      expect(
        find.text(
          'Ce salon n’a pas de propriétaire actif : il ne peut pas être mis '
          'en ligne.',
        ),
        findsOneWidget,
      );
      expect(find.text('Aucun autre salon'), findsOneWidget);
    });

    testWidgets('the history: each request and decision, the code — final '
        'or not — and the note', (t) async {
      await pumpConsole(
        t,
        serving(
          detail(
            events: [
              {
                'kind': 'submitted',
                'at': '2026-11-10T09:00:00.000Z',
                'by': null,
                'refusalCode': null,
                'refusalNote': null,
              },
              {
                'kind': 'refused',
                'at': '2026-11-11T15:30:00.000Z',
                'by': 'admin_1',
                'refusalCode': 'outside_ci',
                'refusalNote': 'Adresse à Dakar',
              },
              {
                'kind': 'submitted',
                'at': '2026-11-12T09:00:00.000Z',
                'by': null,
                'refusalCode': null,
                'refusalNote': null,
              },
            ],
          ),
        ),
        location: path,
      );
      expect(find.text('Refusé'), findsOneWidget);
      expect(find.text('11 nov. 2026 à 15:30 · par admin_1'), findsOneWidget);
      expect(
        find.text('Motif : Hors de Côte d’Ivoire · définitif'),
        findsOneWidget,
      );
      expect(find.text('Note : « Adresse à Dakar »'), findsOneWidget);
    });
  });

  group('the sticky bar', () {
    testWidgets('a pending request: « Refuser » and « Valider la mise en '
        'ligne », both enabled', (t) async {
      await pumpConsole(t, serving(detail()), location: path);
      expect(enabled(t, 'Refuser'), isTrue);
      expect(enabled(t, 'Valider la mise en ligne'), isTrue);
    });

    testWidgets('a suspended salon: « Valider » disabled, and why — in words '
        'and with a way to the suspension', (t) async {
      final server = serving(detail(salonStatus: 'suspended'));
      await pumpConsole(t, server, location: path);
      expect(enabled(t, 'Valider la mise en ligne'), isFalse);
      expect(
        find.text('Salon suspendu : levez d’abord la suspension.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
      await t.tap(find.text('Ouvrir la fiche du salon'));
      await t.pumpAndSettle();
      expect(server.to('/admin/providers/provider_1'), isNotEmpty);
    });

    testWidgets('back from the salon’s page, the request is read again — the '
        'suspension lifted there, « Valider » is enabled here', (t) async {
      final server = serving(
        detail(salonStatus: 'suspended'),
      )..restore = jsonResponse({'status': 'draft', 'reason': 'not_validated'});
      await pumpConsole(t, server, location: path);
      expect(enabled(t, 'Valider la mise en ligne'), isFalse);
      await t.tap(find.text('Ouvrir la fiche du salon'));
      await t.pumpAndSettle();
      // What the server holds once the suspension is lifted.
      server.detail['provider_1'] = jsonResponse(detail());
      await t.tap(find.text('Lever la suspension'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Retour'));
      await t.pumpAndSettle();
      expect(find.byType(AdminSalonValidationDetailScreen), findsOneWidget);
      expect(server.to(detailPath), hasLength(2), reason: 'read again');
      expect(enabled(t, 'Valider la mise en ligne'), isTrue);
      expect(
        find.text('Salon suspendu : levez d’abord la suspension.'),
        findsNothing,
      );
      expect(find.text('Ouvrir la fiche du salon'), findsNothing);
    });

    testWidgets('a validation that did not take the salon live: « Validation '
        'à terminer », the same button, sent from `approved`', (t) async {
      final server = serving(
        detail(
          validation: {
            ...validationJson(
              state: 'approved',
              decidedAt: '2026-11-12T10:00:00.000Z',
            ),
            'decidedBy': 'admin_1',
          },
        ),
      );
      await pumpConsole(t, server, location: path);
      expect(find.text('Validation à terminer'), findsOneWidget);
      expect(
        find.textContaining('Validation à terminer : la validation est'),
        findsOneWidget,
      );
      expect(find.text('Refuser'), findsNothing);
      await t.tap(find.text('Valider la mise en ligne'));
      await t.pumpAndSettle();
      final sent = server.to('$detailPath/approve').single;
      expect(jsonDecode(sent.body), {'from': 'approved'});
    });

    testWidgets('a refused request can be validated from « Refusés » '
        '(from `refused`), and is not refused twice', (t) async {
      final server = serving(
        detail(
          validation: validationJson(
            state: 'refused',
            decidedAt: '2026-11-12T10:00:00.000Z',
            refusal: {'code': 'test_salon', 'note': null, 'final': true},
          ),
        ),
      );
      await pumpConsole(t, server, location: path);
      expect(find.text('Refusé'), findsOneWidget);
      expect(find.text('Refuser'), findsNothing);
      await t.tap(find.text('Valider la mise en ligne'));
      await t.pumpAndSettle();
      expect(jsonDecode(server.to('$detailPath/approve').single.body), {
        'from': 'refused',
      });
    });

    testWidgets('validated and live: nothing to decide, no bar', (t) async {
      await pumpConsole(
        t,
        serving(
          detail(
            salonStatus: 'active',
            validation: validationJson(
              state: 'approved',
              wentLive: true,
              decidedAt: '2026-11-12T10:00:00.000Z',
            ),
          ),
        ),
        location: path,
      );
      expect(find.text('Validé'), findsOneWidget, reason: 'C');
      expect(find.text('Refuser'), findsNothing);
      expect(find.text('Valider la mise en ligne'), findsNothing);
    });

    testWidgets('never asked: said so, and nothing to decide', (t) async {
      await pumpConsole(t, serving(detail(neverAsked: true)), location: path);
      expect(find.text('Aucune demande de mise en ligne'), findsNWidgets(2));
      expect(find.text('Valider la mise en ligne'), findsNothing);
      expect(find.text('Refuser'), findsNothing);
    });
  });

  group('validating', () {
    testWidgets('success: the snackbar, back to the queue — the row has '
        'left « En attente » and the count re-read', (t) async {
      final server = serving(detail());
      final p = await pumpConsole(
        t,
        server,
        location: '/admin/salon-validations',
      );
      expect(find.text('Beauté Divine'), findsOneWidget);
      final countReads = server.requests
          .where((r) => r.url.queryParameters['pageSize'] == '1')
          .length;
      await t.tap(find.text('Beauté Divine'));
      await t.pumpAndSettle();
      // What the server holds once the salon is validated.
      server.queue['pending'] = jsonResponse(queuePage(items: [], total: 0));
      await t.tap(find.text('Valider la mise en ligne'));
      await t.pump();
      await t.pump();
      expect(find.text('Salon validé : il est en ligne.'), findsOneWidget);
      expect(jsonDecode(server.to('$detailPath/approve').single.body), {
        'from': 'pending',
      });
      expect(p.queue.items, isEmpty, reason: 'the row left');
      await t.pumpAndSettle();
      expect(find.byType(AdminSalonValidationsScreen), findsOneWidget);
      expect(find.text('Beauté Divine'), findsNothing);
      expect(
        server.requests
            .where((r) => r.url.queryParameters['pageSize'] == '1')
            .length,
        greaterThan(countReads),
      );
    });

    for (final (name, body, sentence) in [
      (
        'incomplete, its steps named',
        {
          'error': 'incomplete',
          'missing': ['photos', 'availability'],
        },
        'Le salon n’est plus complet : photos, horaires.',
      ),
      (
        'already decided',
        {'error': 'validation_not_pending'},
        'Cette demande a déjà été traitée.',
      ),
      (
        'suspended meanwhile',
        {'error': 'provider_suspended'},
        'Salon suspendu : levez d’abord la suspension.',
      ),
      (
        'no owner',
        {'error': 'no_owner'},
        'Ce salon n’a pas de propriétaire actif : il ne peut pas être mis en '
            'ligne.',
      ),
      (
        'the state moved',
        {'error': 'invalid_state'},
        'L’état du salon a changé entre-temps. Rechargez la page, puis '
            'réessayez.',
      ),
    ]) {
      testWidgets('a 409 ($name): its sentence in the bar, not a snackbar; '
          'the detail re-read', (t) async {
        final server = serving(detail())..approve = jsonResponse(body, 409);
        await pumpConsole(t, server, location: path);
        await t.tap(find.text('Valider la mise en ligne'));
        await t.pumpAndSettle();
        expect(find.text(sentence), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(AdminSalonValidationDetailScreen), findsOneWidget);
        expect(server.to(detailPath), hasLength(2), reason: 're-read');
      });
    }

    testWidgets('a lapsed offer: the sentence, and the way to « Marquer '
        'payé »', (t) async {
      final server = serving(detail())
        ..approve = jsonResponse({
          'error': 'incomplete',
          'missing': ['offer'],
        }, 409);
      await pumpConsole(t, server, location: path);
      await t.tap(find.text('Valider la mise en ligne'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'L’offre du salon n’est plus active : marquez-la payée, puis '
          'validez.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ouvrir la fiche du salon'), findsOneWidget);
    });

    testWidgets('« Rafraîchir » after a 409: the request as it is now — the '
        'last answer\'s sentence and its link do not outlive it', (t) async {
      // Suspended between the read and the click, then lifted elsewhere.
      final server = serving(detail())
        ..approve = jsonResponse({'error': 'provider_suspended'}, 409);
      await pumpConsole(t, server, location: path);
      await t.tap(find.text('Valider la mise en ligne'));
      await t.pumpAndSettle();
      expect(
        find.text('Salon suspendu : levez d’abord la suspension.'),
        findsOneWidget,
      );
      expect(find.text('Ouvrir la fiche du salon'), findsOneWidget);
      await t.tap(find.byTooltip('Rafraîchir'));
      await t.pumpAndSettle();
      expect(
        find.text('Salon suspendu : levez d’abord la suspension.'),
        findsNothing,
      );
      expect(find.text('Ouvrir la fiche du salon'), findsNothing);
      expect(enabled(t, 'Valider la mise en ligne'), isTrue);
    });
  });

  group('refusing', () {
    testWidgets('a code, a note; the request carries them; the snackbar, '
        'back to the queue', (t) async {
      final server = serving(detail());
      await pumpConsole(t, server, location: path);
      await t.tap(find.text('Refuser'));
      await t.pumpAndSettle();
      expect(find.text('Refuser la mise en ligne'), findsOneWidget);
      await t.tap(find.text('Photos insuffisantes'));
      await t.enterText(find.byType(TextField), '  Ajoutez la devanture.  ');
      await t.pump();
      await t.tap(find.widgetWithText(TextButton, 'Refuser'));
      await t.pumpAndSettle();
      expect(jsonDecode(server.to('$detailPath/refuse').single.body), {
        'code': 'photos',
        'note': 'Ajoutez la devanture.',
      });
      expect(find.text('Mise en ligne refusée'), findsOneWidget);
      expect(find.byType(AdminSalonValidationsScreen), findsOneWidget);
    });

    testWidgets('a conflict closes the dialog, and the bar says why', (
      t,
    ) async {
      final server = serving(detail())
        ..refuse = jsonResponse({'error': 'validation_not_pending'}, 409);
      await pumpConsole(t, server, location: path);
      await t.tap(find.text('Refuser'));
      await t.pumpAndSettle();
      await t.tap(find.text('Salon de test'));
      await t.tap(find.widgetWithText(TextButton, 'Refuser'));
      await t.pumpAndSettle();
      expect(find.text('Refuser la mise en ligne'), findsNothing);
      expect(find.text('Cette demande a déjà été traitée.'), findsOneWidget);
      expect(find.byType(AdminSalonValidationDetailScreen), findsOneWidget);
    });

    testWidgets('cancelling leaves nothing behind in the bar', (t) async {
      final server = serving(detail());
      await pumpConsole(t, server, location: path);
      await t.tap(find.text('Refuser'));
      await t.pumpAndSettle();
      await t.tap(find.text('Autre'));
      await t.tap(find.widgetWithText(TextButton, 'Refuser'));
      await t.pumpAndSettle();
      expect(
        find.text('Une note est obligatoire pour le motif « Autre ».'),
        findsOneWidget,
      );
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();
      expect(server.to('$detailPath/refuse'), isEmpty);
      expect(
        find.text('Une note est obligatoire pour le motif « Autre ».'),
        findsNothing,
      );
      expect(find.byType(AppButton), findsWidgets);
    });

    testWidgets('…nor what the server answered inside the dialog', (t) async {
      final server = serving(detail())
        ..refuse = jsonResponse({'error': 'internal_error'}, 500);
      await pumpConsole(t, server, location: path);
      await t.tap(find.text('Refuser'));
      await t.pumpAndSettle();
      await t.tap(find.text('Photos insuffisantes'));
      await t.tap(find.widgetWithText(TextButton, 'Refuser'));
      await t.pumpAndSettle();
      expect(find.text('Une erreur est survenue.'), findsOneWidget);
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();
      expect(server.to('$detailPath/refuse'), hasLength(1));
      expect(find.text('Une erreur est survenue.'), findsNothing);
    });

    testWidgets('the server’s refusal of the note is the dialog’s, never '
        'the bar’s behind it', (t) async {
      const tooLong = 'La note dépasse 500 caractères.';
      final server = serving(detail())
        ..refuse = jsonResponse({'error': 'note_too_long'}, 400);
      await pumpConsole(t, server, location: path);
      await t.tap(find.text('Refuser'));
      await t.pumpAndSettle();
      await t.tap(find.text('Photos insuffisantes'));
      await t.enterText(find.byType(TextField), 'Une note');
      await t.tap(find.widgetWithText(TextButton, 'Refuser'));
      await t.pumpAndSettle();
      // Once: under the note. The bar behind the barrier says nothing.
      expect(find.text(tooLong), findsOneWidget);
      final decorator = t.widget<InputDecorator>(find.byType(InputDecorator));
      expect(decorator.decoration.errorText, tooLong);
    });
  });
}

/// The salon's name, and the owner's business of the same name.
final _salonAndBusiness = findsNWidgets(2);
