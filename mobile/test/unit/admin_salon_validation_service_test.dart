import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/admin_salon_validation.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/salon_validation.dart';
import 'package:myweli/services/admin/admin_response.dart';
import 'package:myweli/services/admin/admin_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

import '../support/admin_salon_validation_fixtures.dart';

/// docs/design/salon-go-live-approval.md §4, §8.2 — every new `AdminService`
/// method against a `MockClient`: the request it sends, the model it reads,
/// and every code its route emits, worded — `missing` included. The bodies are
/// the backend's (`salonValidationResponse`, responses.dart): JSON
/// `{error, missing?}`; and the server from before B0.18 answers an unknown
/// route with dart_frog's plain-text 404 `Route not found`.
void main() {
  late InMemorySessionStore store;

  setUp(() async {
    store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
  });

  AdminService svc(MockClient c) =>
      AdminService(client: c, baseUrl: 'http://x', store: store);

  AdminService answering(int status, Object body) => svc(
    MockClient(
      (_) async =>
          http.Response(body is String ? body : jsonEncode(body), status),
    ),
  );

  /// The older server's answer to a route it does not have.
  final oldServer404 = MockClient(
    (_) async => http.Response('Route not found', 404),
  );

  final p1 = SalonId('provider_1');

  group('salonValidationQueue', () {
    test('asks for the tab, the page and 50 rows; reads the page', () async {
      late Uri asked;
      final s = svc(
        MockClient((req) async {
          asked = req.url;
          expect(req.method, 'GET');
          expect(req.headers['Authorization'], 'Bearer t');
          return http.Response(jsonEncode(queuePage(total: 120)), 200);
        }),
      );
      final res = await s.salonValidationQueue(
        state: SalonValidationState.refused,
        page: 2,
      );
      expect(asked.path, '/admin/salon-validations');
      expect(asked.queryParameters, {
        'state': 'refused',
        'page': '2',
        'pageSize': '50',
      });
      expect(res.success, isTrue);
      final page = res.data!;
      expect(page.total, 120);
      expect(page.items, hasLength(1));
      final item = page.items.single;
      expect(item.providerId, 'provider_1');
      expect(item.name, 'Beauté Divine');
      expect(item.commune, 'Cocody');
      expect(item.countryCode, 'CI');
      expect(item.ownerContact, 'awa@example.com');
      expect(item.kycDocCount, 0);
      expect(item.validation.state, SalonValidationState.pending);
      expect(item.validation.submittedAt, DateTime.utc(2026, 11, 12, 9));
      expect(
        item.dateFor(SalonValidationState.pending),
        DateTime.utc(2026, 11, 12, 9),
      );
    });

    test(
      'the older server: its plain-text 404 is route_missing, not an error',
      () async {
        final res = await svc(
          oldServer404,
        ).salonValidationQueue(state: SalonValidationState.pending);
        expect(res.success, isFalse);
        expect(res.routeMissing, isTrue);
        expect(res.code, kRouteMissingCode);
        expect(
          res.error,
          'Le serveur ne gère pas encore la validation des salons.',
        );
      },
    );

    test('the queue never answers 404 itself: ANY 404 is route_missing — '
        'a JSON one too (a front door that rewrote it)', () async {
      final res = await answering(404, {
        'error': 'not_found',
      }).salonValidationQueue(state: SalonValidationState.pending);
      expect(res.routeMissing, isTrue);
    });

    test('400 invalid_input is worded, and is not route_missing', () async {
      final res = await answering(400, {
        'error': 'invalid_input',
      }).salonValidationQueue(state: SalonValidationState.pending);
      expect(res.routeMissing, isFalse);
      expect(res.code, 'invalid_input');
      expect(res.error, 'Données invalides.');
    });

    test('nothing answered (no session, no network): the session sentence, '
        'not route_missing', () async {
      final s = AdminService(
        client: MockClient((_) async => throw http.ClientException('down')),
        baseUrl: 'http://x',
        store: store,
      );
      final res = await s.salonValidationQueue(
        state: SalonValidationState.pending,
      );
      expect(res.routeMissing, isFalse);
      expect(res.code, 'unauthorized');
      expect(res.error, 'Session expirée ou hors ligne');
    });

    test(
      'a 2xx this build cannot read is an error, never half a page',
      () async {
        final res = await answering(200, {
          'items': [
            {'name': 'no providerId'},
          ],
          'total': 1,
        }).salonValidationQueue(state: SalonValidationState.pending);
        expect(res.success, isFalse);
        expect(res.code, 'bad_response');
        expect(res.error, 'Une erreur est survenue.');
      },
    );
  });

  group('pendingSalonValidationCount', () {
    test('reads the pending tab with ONE row and returns its total', () async {
      late Uri asked;
      final res = await svc(
        MockClient((req) async {
          asked = req.url;
          return http.Response(jsonEncode(queuePage(total: 7)), 200);
        }),
      ).pendingSalonValidationCount();
      expect(asked.path, '/admin/salon-validations');
      expect(asked.queryParameters, {'state': 'pending', 'pageSize': '1'});
      expect(res.data, 7);
    });

    test('the older server: route_missing', () async {
      final res = await svc(oldServer404).pendingSalonValidationCount();
      expect(res.success, isFalse);
      expect(res.routeMissing, isTrue);
    });
  });

  group('salonValidationDetail', () {
    test('reads the salon, the offer, the owner, the validation and the '
        'history', () async {
      late Uri asked;
      final res = await svc(
        MockClient((req) async {
          asked = req.url;
          return http.Response(jsonEncode(detailJson()), 200);
        }),
      ).salonValidationDetail(p1);
      expect(asked.path, '/admin/salons/provider_1/validation');
      final d = res.data!;
      expect(d.salon.id, 'provider_1');
      expect(d.salon.name, 'Beauté Divine');
      expect(d.salon.category, 'coiffure');
      expect(d.salon.imageUrls, hasLength(3));
      expect(d.salon.services.first.name, 'Tresses');
      expect(d.salon.services.first.price, 15000);
      expect(d.salon.services.first.priceMax, 25000);
      expect(d.salon.weeklyHours[0]!.single.start!.hour, 9);
      expect(d.salon.weeklyHours[6], isEmpty, reason: 'Sunday: closed');
      expect(d.salon.weeklyHours.containsKey(3), isFalse, reason: 'absent');
      expect(d.salon.latitude, 5.36);
      expect(d.salon.phoneNumber, '+2250707070707');
      expect(d.offer!.status, SalonOfferStatus.trial);
      expect(d.owner!.accountId, 'acc_1');
      expect(d.owner!.accountAgeDays, 12);
      expect(d.owner!.otherSalons.single.id, 'provider_2');
      expect(d.validation!.state, SalonValidationState.pending);
      expect(d.validation!.decidedBy, isNull);
      expect(d.events.single.at, DateTime.utc(2026, 11, 12, 9));
      expect(d.approveFrom, SalonValidationState.pending);
      expect(d.canRefuse, isTrue);
    });

    test(
      'a JSON 404 not_found is an unknown salon: « Introuvable. »',
      () async {
        final res = await answering(404, {
          'error': 'not_found',
        }).salonValidationDetail(p1);
        expect(res.routeMissing, isFalse);
        expect(res.code, 'not_found');
        expect(res.error, 'Introuvable.');
      },
    );

    test('the older server\'s plain-text 404 is route_missing', () async {
      final res = await svc(oldServer404).salonValidationDetail(p1);
      expect(res.routeMissing, isTrue);
      expect(res.code, kRouteMissingCode);
    });

    test('an id from a crafted link stays ONE path segment', () async {
      late Uri asked;
      await svc(
        MockClient((req) async {
          asked = req.url;
          return http.Response(jsonEncode(detailJson()), 200);
        }),
      ).salonValidationDetail(SalonId('../../kyc/acc1'));
      expect(asked.path, '/admin/salons/..%2F..%2Fkyc%2Facc1/validation');
      expect(asked.pathSegments, [
        'admin',
        'salons',
        '../../kyc/acc1',
        'validation',
      ]);
    });

    test('a salon under review may be incomplete: no services, no hours, '
        'no pin, no owner, no offer, never asked — still read', () async {
      final res = await answering(200, {
        'salon': {'id': 'provider_1', 'status': 'draft'},
        'offer': null,
        'owner': null,
        'validation': null,
        'events': <Object>[],
      }).salonValidationDetail(p1);
      final d = res.data!;
      expect(d.salon.name, isNull);
      expect(d.salon.services, isEmpty);
      expect(d.salon.weeklyHours, isEmpty);
      expect(d.salon.hasPin, isFalse);
      expect(d.owner, isNull);
      expect(d.offer, isNull);
      expect(d.validation, isNull);
      expect(d.approveFrom, isNull);
      expect(d.canApprove, isFalse);
      expect(d.canRefuse, isFalse);
    });
  });

  group('approveSalonValidation', () {
    test(
      'posts the state the screen read as `from`; reads the answer',
      () async {
        late http.Request sent;
        final res = await svc(
          MockClient((req) async {
            sent = req;
            return http.Response(
              jsonEncode({
                'salonStatus': 'active',
                'validation': {
                  'state': 'approved',
                  'submittedAt': '2026-11-12T09:00:00.000Z',
                  'decidedAt': '2026-11-12T10:00:00.000Z',
                  'wentLive': true,
                },
              }),
              200,
            );
          }),
        ).approveSalonValidation(p1, from: SalonValidationState.refused);
        expect(sent.method, 'POST');
        expect(sent.url.path, '/admin/salons/provider_1/validation/approve');
        expect(sent.headers['content-type'], startsWith('application/json'));
        expect(jsonDecode(sent.body), {'from': 'refused'});
        expect(res.data!.salonStatus, 'active');
        expect(res.data!.validation!.state, SalonValidationState.approved);
        expect(res.data!.validation!.wentLive, isTrue);
      },
    );

    test('a 2xx without its salonStatus is bad_response — never « Salon '
        'validé » on a state nobody read', () async {
      for (final body in ['', '[]', '{}', '{"validation": null}']) {
        final res = await answering(
          200,
          body,
        ).approveSalonValidation(p1, from: SalonValidationState.pending);
        expect(res.success, isFalse, reason: body);
        expect(res.code, 'bad_response', reason: body);
        expect(res.data, isNull, reason: body);
      }
    });

    // §4.3 « Feedback » — the four sentences the spec words, verbatim.
    final spec409 = {
      'validation_not_pending': 'Cette demande a déjà été traitée.',
      'provider_suspended': 'Salon suspendu : levez d’abord la suspension.',
    };
    for (final e in spec409.entries) {
      test('409 ${e.key} → « ${e.value} »', () async {
        final res = await answering(409, {
          'error': e.key,
        }).approveSalonValidation(p1, from: SalonValidationState.pending);
        expect(res.code, e.key);
        expect(res.error, e.value);
        expect(res.missing, isEmpty);
      });
    }

    test('409 incomplete keeps `missing` and names each step', () async {
      final res = await answering(409, {
        'error': 'incomplete',
        'missing': ['photos', 'availability'],
      }).approveSalonValidation(p1, from: SalonValidationState.pending);
      expect(res.code, 'incomplete');
      expect(res.missing, ['photos', 'availability']);
      expect(res.error, 'Le salon n’est plus complet : photos, horaires.');
    });

    test('a `missing` that is not a list is no steps, not a crash', () async {
      final res = await answering(409, {
        'error': 'incomplete',
        'missing': 'photos',
      }).approveSalonValidation(p1, from: SalonValidationState.pending);
      expect(res.code, 'incomplete');
      expect(res.missing, isEmpty);
      expect(res.error, 'Le salon n’est plus complet.');
    });

    test('every gate key has a French name — never the wire key', () async {
      final res = await answering(409, {
        'error': 'incomplete',
        'missing': ['profile', 'location', 'services'],
      }).approveSalonValidation(p1, from: SalonValidationState.pending);
      expect(
        res.error,
        'Le salon n’est plus complet : profil de l’entreprise, position sur '
        'la carte, services.',
      );
    });

    test(
      'an expired offer is `incomplete` + `offer`: its own sentence',
      () async {
        final res = await answering(409, {
          'error': 'incomplete',
          'missing': ['offer'],
        }).approveSalonValidation(p1, from: SalonValidationState.approved);
        expect(res.missing, ['offer']);
        expect(
          res.error,
          'L’offre du salon n’est plus active : marquez-la payée, puis validez.',
        );
      },
    );

    test('steps AND the offer: both sentences, steps first', () async {
      final res = await answering(409, {
        'error': 'incomplete',
        'missing': ['photos', 'offer'],
      }).approveSalonValidation(p1, from: SalonValidationState.pending);
      expect(
        res.error,
        'Le salon n’est plus complet : photos. L’offre du salon n’est plus '
        'active : marquez-la payée, puis validez.',
      );
    });

    final newCopy409 = {
      'no_owner':
          'Ce salon n’a pas de propriétaire actif : il ne peut pas être mis '
          'en ligne.',
      'invalid_state':
          'L’état du salon a changé entre-temps. Rechargez la page, puis '
          'réessayez.',
    };
    for (final e in newCopy409.entries) {
      test('409 ${e.key} is worded', () async {
        final res = await answering(409, {
          'error': e.key,
        }).approveSalonValidation(p1, from: SalonValidationState.pending);
        expect(res.code, e.key);
        expect(res.error, e.value);
      });
    }

    test(
      '400 invalid_input / invalid_body, 404 not_found are worded',
      () async {
        for (final (status, code, sentence) in [
          (400, 'invalid_input', 'Données invalides.'),
          (400, 'invalid_body', 'Données invalides.'),
          (404, 'not_found', 'Introuvable.'),
        ]) {
          final res = await answering(status, {
            'error': code,
          }).approveSalonValidation(p1, from: SalonValidationState.pending);
          expect(res.code, code);
          expect(res.error, sentence);
        }
      },
    );

    test('the older server\'s plain-text 404 is route_missing', () async {
      final res = await svc(
        oldServer404,
      ).approveSalonValidation(p1, from: SalonValidationState.pending);
      expect(res.routeMissing, isTrue);
    });
  });

  group('refuseSalonValidation', () {
    test('posts the code and the trimmed note; reads the validation', () async {
      late http.Request sent;
      final res =
          await svc(
            MockClient((req) async {
              sent = req;
              return http.Response(
                jsonEncode({
                  'validation': {
                    'state': 'refused',
                    'decidedAt': '2026-11-12T10:00:00.000Z',
                    'wentLive': false,
                    'refusal': {
                      'code': 'outside_ci',
                      'note': 'Adresse à Dakar',
                      'final': true,
                    },
                  },
                }),
                200,
              );
            }),
          ).refuseSalonValidation(
            p1,
            code: 'outside_ci',
            note: '  Adresse à Dakar ',
          );
      expect(sent.url.path, '/admin/salons/provider_1/validation/refuse');
      expect(jsonDecode(sent.body), {
        'code': 'outside_ci',
        'note': 'Adresse à Dakar',
      });
      expect(res.data!.state, SalonValidationState.refused);
      expect(res.data!.refusal!.code, 'outside_ci');
      expect(res.data!.refusal!.isFinal, isTrue);
      expect(res.data!.refusal!.note, 'Adresse à Dakar');
    });

    test('a blank note is left out of the body', () async {
      late http.Request sent;
      await svc(
        MockClient((req) async {
          sent = req;
          return http.Response(
            jsonEncode({
              'validation': {'state': 'refused', 'wentLive': false},
            }),
            200,
          );
        }),
      ).refuseSalonValidation(p1, code: 'photos', note: '   ');
      expect(jsonDecode(sent.body), {'code': 'photos'});
    });

    for (final (status, code, sentence) in [
      (
        400,
        'note_required',
        'Une note est obligatoire pour le motif « Autre ».',
      ),
      (400, 'note_too_long', 'La note dépasse 500 caractères.'),
      (400, 'invalid_input', 'Données invalides.'),
      (409, 'validation_not_pending', 'Cette demande a déjà été traitée.'),
      (404, 'not_found', 'Introuvable.'),
    ]) {
      test('$status $code → « $sentence »', () async {
        final res = await answering(status, {
          'error': code,
        }).refuseSalonValidation(p1, code: 'other', note: 'x');
        expect(res.code, code);
        expect(res.error, sentence);
      });
    }
  });

  group('restoreProvider — two servers (§9.2)', () {
    Future<AdminResponse<RestoreOutcome>> restore(int status, Object body) =>
        answering(status, body).restoreProvider(p1);

    test('the older server: the whole salon, no `reason` key → legacy, '
        'live', () async {
      final res = await restore(200, {
        'id': 'provider_1',
        'name': 'Beauté Divine',
        'status': 'active',
        'imageUrls': <String>[],
      });
      final o = res.data!;
      expect(o.legacy, isTrue);
      expect(o.status, 'active');
      expect(o.isLive, isTrue);
      expect(o.reason, isNull);
    });

    test('B0.18, live: {status: active, reason: null}', () async {
      final o = (await restore(200, {
        'status': 'active',
        'reason': null,
      })).data!;
      expect(o.legacy, isFalse);
      expect(o.isLive, isTrue);
    });

    test('B0.18, offline: {status: draft, reason}', () async {
      final o = (await restore(200, {
        'status': 'draft',
        'reason': 'offer_not_live',
      })).data!;
      expect(o.legacy, isFalse);
      expect(o.isLive, isFalse);
      expect(o.status, 'draft');
      expect(o.reason, 'offer_not_live');
    });

    test('a 2xx that is neither server\'s answer is bad_response — never '
        '« Salon remis en ligne » on a state nobody read', () async {
      for (final body in [
        '',
        '[]',
        '{}',
        '{"id": "provider_1", "status": null}',
        '{"reason": null}',
        '{"status": "suspended", "reason": null}',
      ]) {
        final res = await restore(200, body);
        expect(res.success, isFalse, reason: body);
        expect(res.code, 'bad_response', reason: body);
        expect(res.data, isNull, reason: body);
      }
    });

    test('B0.18: 409 not_suspended is worded', () async {
      final res = await restore(409, {'error': 'not_suspended'});
      expect(res.code, 'not_suspended');
      expect(res.error, 'Ce salon n’est pas suspendu.');
    });

    test('both: 404 not_found → « Introuvable. »', () async {
      final res = await restore(404, {'error': 'not_found'});
      expect(res.routeMissing, isFalse);
      expect(res.error, 'Introuvable.');
    });

    test('the route exists on both servers: a plain 404 is never « a server '
        'from before B0.18 »', () async {
      final res = await svc(oldServer404).restoreProvider(p1);
      expect(res.routeMissing, isFalse);
      expect(res.error, 'Une erreur est survenue.');
    });
  });

  test('every code the new routes emit has its own sentence — none falls to '
      '« Une erreur est survenue. »', () {
    // salonValidationResponse (responses.dart) + the two input codes of the
    // approve/refuse routes + publish's final refusal (never an admin answer,
    // worded anyway) + the console's own route_missing.
    const codes = [
      'not_found',
      'incomplete',
      'validation_not_pending',
      'validation_refused_final',
      'not_suspended',
      'provider_suspended',
      'no_owner',
      'invalid_state',
      'note_required',
      'note_too_long',
      'invalid_input',
      'invalid_body',
      kRouteMissingCode,
    ];
    final generic = AdminService.sentenceFor(null);
    // The salon routes' answers are worded by salonSentenceFor (_typed).
    for (final c in codes) {
      expect(AdminService.salonSentenceFor(c), isNot(generic), reason: c);
      expect(
        AdminService.salonSentenceFor(c).toLowerCase(),
        isNot(contains('vérif')),
        reason: '« vérification » is KYC\'s word (spec, Vocabulary): $c',
      );
    }
  });

  test('invalid_state: the salon routes word it for the salon; the shared '
      'map keeps it neutral, for every other admin endpoint, the KYC '
      'decisions included (admin-kyc-queue-submitted.md §4.5)', () {
    expect(
      AdminService.salonSentenceFor('invalid_state'),
      'L’état du salon a changé entre-temps. Rechargez la page, puis '
      'réessayez.',
    );
    expect(
      AdminService.sentenceFor('invalid_state'),
      'Cette action n’est plus possible.',
    );
    for (final c in ['not_found', 'no_owner', 'validation_not_pending']) {
      expect(
        AdminService.salonSentenceFor(c),
        AdminService.sentenceFor(c),
        reason: c,
      );
    }
  });
}
