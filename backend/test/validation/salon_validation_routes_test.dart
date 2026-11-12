import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/demo_seam.dart';
import 'package:test/test.dart';

import 'validation_routes_harness.dart';
import 'validation_world.dart';

/// B0.18 stage 3 — the routes (docs/design/salon-go-live-approval.md §3.1,
/// §3.4, §3.5, §3.8): what each answer is ON THE WIRE. The services' every
/// branch is pinned in the neighbouring service tests; this file pins the
/// status codes and bodies the clients read — the 202 that keeps an old
/// build from saying « en ligne », the 409s the console words, the 400s, the
/// 405s — and that every admin route sits behind the admin boundary.
void main() {
  late ValidationWorld w;
  late ValidationRoutes routes;

  setUp(() {
    w = ValidationWorld();
    routes = ValidationRoutes(w);
  });

  /// A salon whose owner asked to go live.
  Future<({String id, String ownerId})> pending({
    String name = 'Salon Awa',
  }) async {
    final s = await w.salon(name: name);
    final r = await w.provisioning.publish(s.id);
    expect(r.accepted, isTrue, reason: '${r.error} ${r.data}');
    return s;
  }

  /// A salon MyWeli validated, live.
  Future<({String id, String ownerId})> live() async {
    final s = await w.salon();
    await w.validateLive(s.id);
    return s;
  }

  String owner(({String id, String ownerId}) s) =>
      routes.token(s.ownerId, 'provider');

  var staffCount = 0;

  /// A fresh account that is an active MANAGER of [salonId] — a member who
  /// does not hold `salon.publish` — and its token.
  Future<({String token, String accountId})> managerOf(String salonId) async {
    staffCount++;
    final email = 'manager$staffCount@salon.pro';
    final reg = await w.auth.register(
      businessName: 'Équipe',
      businessType: 'salon',
      phoneNumber: '+22501000099${staffCount.toString().padLeft(2, '0')}',
      email: email,
      authProvider: 'google',
      googleSub: 'sub-manager-$staffCount',
    );
    final invited = await w.members.invite(
      providerId: salonId,
      email: email,
      role: 'manager',
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
    );
    final active = await w.members.activate(invited!.id, reg.provider!.id);
    expect(active?.status, 'active');
    return (
      token: routes.token(reg.provider!.id, 'provider'),
      accountId: reg.provider!.id,
    );
  }

  group('POST /providers/{id}/publish — a REQUEST, mapped', () {
    test('never asked → 202 {validation: pending}; asking again → 202, the '
        'same body, ONE event; no trial, no rebuild, still draft', () async {
      final s = await w.salon();
      final first = await routes.publish(s.id, bearer: owner(s));
      expect(first.statusCode, HttpStatus.accepted);
      final body = await bodyOf(first);
      expect(body.keys, ['validation']);
      final v = body['validation'] as Map;
      expect(v['state'], 'pending');
      expect(v['wentLive'], isFalse);
      expect(v['submittedAt'], isNotNull);

      final again = await routes.publish(s.id, bearer: owner(s));
      expect(again.statusCode, HttpStatus.accepted);
      expect(await bodyOf(again), body);

      expect(await w.validations.events(s.id), hasLength(1));
      expect(w.adminMail.sent, hasLength(1));
      expect(await w.subs.byProvider(s.id), isNull);
      expect(w.rebuild.reasons, isEmpty);
      expect(await w.statusOf(s.id), 'draft');
    });

    test('validated, not yet live (the admin finishing) → 202', () async {
      final s = await pending();
      await w.validations.decide(
        s.id,
        from: 'pending',
        to: 'approved',
        adminId: 'admin_1',
      );
      final res = await routes.publish(s.id, bearer: owner(s));
      expect(res.statusCode, HttpStatus.accepted);
      final v = (await bodyOf(res))['validation'] as Map;
      expect(v['state'], 'approved');
      expect(v['wentLive'], isFalse);
      expect(await w.statusOf(s.id), 'draft');
    });

    test('already live → 200 with the salon (idempotent)', () async {
      final s = await live();
      final res = await routes.publish(s.id, bearer: owner(s));
      expect(res.statusCode, HttpStatus.ok);
      final body = await bodyOf(res);
      expect(body['id'], s.id);
      expect(body['status'], 'active');
      expect(body.containsKey('validation'), isFalse);
    });

    test('validated, was live, back to draft with a LIVE offer → 200 live '
        '(the republish)', () async {
      final s = await live();
      await w.providers.setStatus(s.id, 'draft');
      final res = await routes.publish(s.id, bearer: owner(s));
      expect(res.statusCode, HttpStatus.ok);
      expect((await bodyOf(res))['status'], 'active');
      expect(await w.isPublic(s.id), isTrue);
    });

    test(
      'validated, was live, its offer EXPIRED → 409 incomplete [offer]',
      () async {
        final s = await live();
        await w.providers.setStatus(s.id, 'draft');
        w.now = w.now.add(const Duration(days: 200));
        final res = await routes.publish(s.id, bearer: owner(s));
        expect(res.statusCode, HttpStatus.conflict);
        expect(await bodyOf(res), {
          'error': 'incomplete',
          'missing': ['offer'],
        });
      },
    );

    test('incomplete → 409 incomplete + the missing keys', () async {
      final s = await w.salon(complete: false);
      final res = await routes.publish(s.id, bearer: owner(s));
      expect(res.statusCode, HttpStatus.conflict);
      final body = await bodyOf(res);
      expect(body['error'], 'incomplete');
      expect(
        body['missing'],
        containsAll(['profile', 'location', 'services', 'photos']),
      );
    });

    test('a FINAL refusal → 409 validation_refused_final, no missing, '
        'nothing recorded', () async {
      final s = await pending();
      await w.service.refuse(
        s.id,
        code: 'outside_ci',
        note: null,
        adminId: 'admin_1',
      );
      final res = await routes.publish(s.id, bearer: owner(s));
      expect(res.statusCode, HttpStatus.conflict);
      expect(await bodyOf(res), {'error': 'validation_refused_final'});
      expect((await w.validations.get(s.id))!.state, 'refused');
    });

    test('a refusal that is NOT final → 202, pending again', () async {
      final s = await pending();
      await w.service.refuse(
        s.id,
        code: 'photos',
        note: null,
        adminId: 'admin_1',
      );
      final res = await routes.publish(s.id, bearer: owner(s));
      expect(res.statusCode, HttpStatus.accepted);
      expect(((await bodyOf(res))['validation'] as Map)['state'], 'pending');
    });

    test(
      '403s: the demo salon, a suspended salon, a salon not owned',
      () async {
        final demo = await w.salon(email: kDemoProviderEmail);
        final locked = await routes.publish(demo.id, bearer: owner(demo));
        expect(locked.statusCode, HttpStatus.forbidden);
        expect(await bodyOf(locked), {'error': 'demo_account_locked'});

        final s = await w.salon();
        await w.providers.setStatus(s.id, 'suspended');
        final suspended = await routes.publish(s.id, bearer: owner(s));
        expect(suspended.statusCode, HttpStatus.forbidden);
        expect(await bodyOf(suspended), {'error': 'provider_suspended'});

        final other = await w.salon();
        final cross = await routes.publish(other.id, bearer: owner(s));
        expect(cross.statusCode, HttpStatus.forbidden);
        expect(await bodyOf(cross), {'error': 'forbidden'});
        expect(await w.validations.get(other.id), isNull);
      },
    );

    test(
      '404 — the salon row is gone; 405; 401; a consumer token 403',
      () async {
        const ghost = 'provider_gone';
        final s = await w.salon();
        await w.members.ensureOwner(
          providerId: ghost,
          accountId: s.ownerId,
          email: 'owner@salon.pro',
        );
        final gone = await routes.publish(ghost, bearer: owner(s));
        expect(gone.statusCode, HttpStatus.notFound);
        expect(await bodyOf(gone), {'error': 'not_found'});

        final get = await routes.publish(s.id, bearer: owner(s), method: 'GET');
        expect(get.statusCode, HttpStatus.methodNotAllowed);
        expect(await bodyOf(get), {'error': 'method_not_allowed'});

        final anon = await routes.publish(s.id, bearer: null);
        expect(anon.statusCode, HttpStatus.unauthorized);

        final consumer = await routes.publish(
          s.id,
          bearer: routes.token('u1', 'user'),
        );
        expect(consumer.statusCode, HttpStatus.forbidden);
        expect(await w.validations.get(s.id), isNull);
      },
    );
  });

  group('the admin boundary — every new route, and restore', () {
    /// Each admin route, called with no token, with a provider's, with a
    /// consumer's: 401, 403, 403 — and nothing written.
    test('no token → 401; a provider or consumer token → 403; nothing '
        'written', () async {
      final s = await pending();
      final calls =
          <String, Future<Response> Function({String? bearer, bool anonymous})>{
            'GET /admin/salon-validations': ({bearer, anonymous = false}) =>
                routes.queue(bearer: bearer, anonymous: anonymous),
            'GET /admin/salons/{id}/validation':
                ({bearer, anonymous = false}) =>
                    routes.detail(s.id, bearer: bearer, anonymous: anonymous),
            'POST …/validation/approve': ({bearer, anonymous = false}) =>
                routes.approve(
                  s.id,
                  json: {'from': 'pending'},
                  bearer: bearer,
                  anonymous: anonymous,
                ),
            'POST …/validation/refuse': ({bearer, anonymous = false}) =>
                routes.refuse(
                  s.id,
                  json: {'code': 'photos'},
                  bearer: bearer,
                  anonymous: anonymous,
                ),
            'POST /admin/providers/{id}/restore':
                ({bearer, anonymous = false}) =>
                    routes.restore(s.id, bearer: bearer, anonymous: anonymous),
            'GET /admin/analytics/overview': ({bearer, anonymous = false}) =>
                routes.overview(bearer: bearer, anonymous: anonymous),
          };
      for (final MapEntry(key: name, value: call) in calls.entries) {
        final anon = await call(anonymous: true);
        expect(anon.statusCode, HttpStatus.unauthorized, reason: name);
        expect(await bodyOf(anon), {'error': 'unauthorized'}, reason: name);
        for (final role in ['provider', 'user']) {
          final res = await call(bearer: routes.token(s.ownerId, role));
          expect(res.statusCode, HttpStatus.forbidden, reason: '$name $role');
          expect(await bodyOf(res), {'error': 'forbidden'}, reason: name);
        }
      }
      // The salon's owner holds `salon.publish` — not the admin's decision.
      expect((await w.validations.get(s.id))!.state, 'pending');
      expect(await w.statusOf(s.id), 'draft');
      expect((await w.audit.list()).total, 0);
    });

    test('a wrong verb → 405 on each', () async {
      final s = await pending();
      final answers = [
        await routes.queue(method: 'POST'),
        await routes.detail(s.id, method: 'DELETE'),
        await routes.approve(s.id, method: 'GET'),
        await routes.refuse(s.id, method: 'PUT'),
        await routes.restore(s.id, method: 'GET'),
        await routes.overview(method: 'POST'),
      ];
      for (final res in answers) {
        expect(res.statusCode, HttpStatus.methodNotAllowed);
        expect(await bodyOf(res), {'error': 'method_not_allowed'});
      }
    });
  });

  group('GET /admin/salon-validations', () {
    test('defaults to « En attente », oldest first, in the paginated '
        'envelope', () async {
      final a = await pending(name: 'Salon A');
      w.now = w.now.add(const Duration(hours: 1));
      final b = await pending(name: 'Salon B');
      final res = await routes.queue();
      expect(res.statusCode, HttpStatus.ok);
      final body = await bodyOf(res);
      expect(body['page'], 1);
      expect(body['pageSize'], 50);
      expect(body['total'], 2);
      final items = (body['items'] as List).cast<Map<String, dynamic>>();
      expect([for (final i in items) i['providerId']], [a.id, b.id]);
      expect(items.first['name'], 'Salon A');
      expect((items.first['validation'] as Map)['state'], 'pending');
      expect(items.first['ownerContact'], contains('@'));
      expect(items.first['kycDocCount'], 0);
    });

    test('the tabs: refused and approved', () async {
      final r = await pending();
      await w.service.refuse(
        r.id,
        code: 'photos',
        note: null,
        adminId: 'admin_1',
      );
      final l = await live();
      final refused = await bodyOf(await routes.queue(query: 'state=refused'));
      expect(
        [for (final i in refused['items'] as List) i['providerId']],
        [r.id],
      );
      final approved = await bodyOf(
        await routes.queue(query: 'state=approved'),
      );
      expect([
        for (final i in approved['items'] as List) i['providerId'],
      ], contains(l.id));
      final pendingTab = await bodyOf(await routes.queue(query: 'state='));
      expect(pendingTab['total'], 0);
    });

    test('pageSize and page are CLAMPED like the other admin lists', () async {
      await pending();
      Future<Map<String, dynamic>> q(String query) async =>
          bodyOf(await routes.queue(query: query));
      expect((await q('pageSize=1000'))['pageSize'], 100);
      expect((await q('pageSize=0'))['pageSize'], 1);
      expect((await q('pageSize=-5&page=-2'))['page'], 1);
      expect((await q('pageSize=abc&page=xyz'))['pageSize'], 50);
      final one = await q('state=pending&pageSize=1');
      expect(one['total'], 1);
      expect(one['items'], hasLength(1));
    });

    test('an unknown state → 400 invalid_input', () async {
      final res = await routes.queue(query: 'state=everything');
      expect(res.statusCode, HttpStatus.badRequest);
      expect(await bodyOf(res), {'error': 'invalid_input'});
    });
  });

  group('GET /admin/salons/{id}/validation', () {
    test('200: the salon, the offer, the owner, the validation with who '
        'decided, the history', () async {
      final s = await pending();
      await w.service.refuse(
        s.id,
        code: 'other',
        note: 'Le nom ne correspond pas.',
        adminId: 'admin_9',
      );
      final res = await routes.detail(s.id);
      expect(res.statusCode, HttpStatus.ok);
      final body = await bodyOf(res);
      expect((body['salon'] as Map)['id'], s.id);
      expect(body['offer'], isNull);
      final owner = body['owner'] as Map;
      expect(owner['accountId'], s.ownerId);
      expect(owner['kycDocCount'], 0);
      final v = body['validation'] as Map;
      expect(v['state'], 'refused');
      expect(v['decidedBy'], 'admin_9');
      expect((v['refusal'] as Map)['note'], 'Le nom ne correspond pas.');
      expect(
        [for (final e in body['events'] as List) e['kind']],
        ['submitted', 'refused'],
      );
    });

    test('never asked → validation null; unknown salon → 404', () async {
      final s = await w.salon();
      expect((await bodyOf(await routes.detail(s.id)))['validation'], isNull);
      final res = await routes.detail('provider_nope');
      expect(res.statusCode, HttpStatus.notFound);
      expect(await bodyOf(res), {'error': 'not_found'});
    });
  });

  group('POST /admin/salons/{id}/validation/approve', () {
    test('200 {salonStatus: active, validation} — public now', () async {
      final s = await pending();
      final res = await routes.approve(s.id, json: {'from': 'pending'});
      expect(res.statusCode, HttpStatus.ok);
      final body = await bodyOf(res);
      expect(body['salonStatus'], 'active');
      final v = body['validation'] as Map;
      expect(v['state'], 'approved');
      expect(v['wentLive'], isTrue);
      expect(v.containsKey('decidedBy'), isFalse);
      expect(await w.isPublic(s.id), isTrue);
      expect(w.rebuild.reasons, ['salon.approved']);
    });

    test(
      '400 invalid_body: not JSON, an array, null; nothing written',
      () async {
        final s = await pending();
        for (final raw in ['not json', '[1,2]', 'null', '']) {
          final res = await routes.approve(s.id, rawBody: raw);
          expect(res.statusCode, HttpStatus.badRequest, reason: raw);
          expect(await bodyOf(res), {'error': 'invalid_body'}, reason: raw);
        }
        expect((await w.validations.get(s.id))!.state, 'pending');
      },
    );

    test('400 invalid_input: `from` missing, unknown, not text', () async {
      final s = await pending();
      for (final body in [
        <String, dynamic>{},
        {'from': 'live'},
        {'from': 1},
      ]) {
        final res = await routes.approve(s.id, json: body);
        expect(res.statusCode, HttpStatus.badRequest, reason: '$body');
        expect(await bodyOf(res), {'error': 'invalid_input'});
      }
      expect((await w.validations.get(s.id))!.state, 'pending');
    });

    test('404 unknown salon', () async {
      final res = await routes.approve(
        'provider_nope',
        json: {'from': 'pending'},
      );
      expect(res.statusCode, HttpStatus.notFound);
      expect(await bodyOf(res), {'error': 'not_found'});
    });

    test('409 provider_suspended — nothing written', () async {
      final s = await pending();
      await w.providers.setStatus(s.id, 'suspended');
      final res = await routes.approve(s.id, json: {'from': 'pending'});
      expect(res.statusCode, HttpStatus.conflict);
      expect(await bodyOf(res), {'error': 'provider_suspended'});
      expect((await w.validations.get(s.id))!.state, 'pending');
    });

    test('409 incomplete CARRIES missing — the gate re-run now', () async {
      final s = await pending();
      await w.providers.updateProfile(s.id, {'imageUrls': <String>[]});
      final res = await routes.approve(s.id, json: {'from': 'pending'});
      expect(res.statusCode, HttpStatus.conflict);
      expect(await bodyOf(res), {
        'error': 'incomplete',
        'missing': ['photos'],
      });
      expect((await w.validations.get(s.id))!.state, 'pending');
    });

    test('409 incomplete [offer] — an offer row no longer live', () async {
      final s = await pending();
      await w.subs.create(
        providerId: s.id,
        tier: 'pro',
        trialEndsAt: w.now.subtract(const Duration(days: 100)),
      );
      final res = await routes.approve(s.id, json: {'from': 'pending'});
      expect(res.statusCode, HttpStatus.conflict);
      expect(await bodyOf(res), {
        'error': 'incomplete',
        'missing': ['offer'],
      });
    });

    test(
      '409 validation_not_pending — the wrong `from`, a second click',
      () async {
        final s = await pending();
        final stale = await routes.approve(s.id, json: {'from': 'refused'});
        expect(stale.statusCode, HttpStatus.conflict);
        expect(await bodyOf(stale), {'error': 'validation_not_pending'});

        expect(
          (await routes.approve(s.id, json: {'from': 'pending'})).statusCode,
          HttpStatus.ok,
        );
        final again = await routes.approve(s.id, json: {'from': 'pending'});
        expect(again.statusCode, HttpStatus.conflict);
        expect(await bodyOf(again), {'error': 'validation_not_pending'});
        expect((await w.audit.list(action: 'salon.approve')).total, 1);
      },
    );

    test('409 no_owner — nobody could run it; not public', () async {
      final created = await w.providers.createSalon(
        name: 'Sans propriétaire',
        category: 'salon',
        phoneNumber: '+2250700000009',
      );
      final id = created['id'] as String;
      await w.providers.updateProfile(id, completeProfile);
      await w.validations.submit(id, w.now);
      final res = await routes.approve(id, json: {'from': 'pending'});
      expect(res.statusCode, HttpStatus.conflict);
      expect(await bodyOf(res), {'error': 'no_owner'});
      expect(await w.isPublic(id), isFalse);
    });

    test('200 — « Validation à terminer » on a salon an older image left '
        'active: handed back, then taken live by the validation', () async {
      final s = await pending();
      await w.validations.decide(
        s.id,
        from: 'pending',
        to: 'approved',
        adminId: 'admin_1',
      );
      await w.providers.setStatus(s.id, 'active');
      final res = await routes.approve(s.id, json: {'from': 'approved'});
      expect(res.statusCode, HttpStatus.ok);
      expect((await w.validations.get(s.id))!.wentLive, isTrue);
      expect(await w.statusOf(s.id), 'active');
    });

    test('409 invalid_state — the salon left draft between the hand-back '
        "and the going-live (an older image's publish racing it)", () async {
      late OlderImagePublishRacing racing;
      w = ValidationWorld(
        validationsOf: (providers, members) => racing = OlderImagePublishRacing(
          providers: providers,
          members: members,
        ),
      );
      routes = ValidationRoutes(w);
      final s = await pending();
      await w.validations.decide(
        s.id,
        from: 'pending',
        to: 'approved',
        adminId: 'admin_1',
      );
      racing.armed = true;
      final res = await routes.approve(s.id, json: {'from': 'approved'});
      expect(res.statusCode, HttpStatus.conflict);
      expect(await bodyOf(res), {'error': 'invalid_state'});
      expect((await w.validations.get(s.id))!.wentLive, isFalse);
    });
  });

  group('POST /admin/salons/{id}/validation/refuse', () {
    test('200 {validation} with the refusal; still draft', () async {
      final s = await pending();
      final res = await routes.refuse(
        s.id,
        json: {'code': 'other', 'note': '  Envoyez une photo de la façade. '},
      );
      expect(res.statusCode, HttpStatus.ok);
      final v = (await bodyOf(res))['validation'] as Map;
      expect(v['state'], 'refused');
      expect(v['refusal'], {
        'code': 'other',
        'note': 'Envoyez une photo de la façade.',
        'final': false,
      });
      expect(await w.statusOf(s.id), 'draft');
    });

    test('400s: invalid_body, invalid_input, note_required, note_too_long — '
        'nothing written', () async {
      final s = await pending();
      Future<void> refused(Object? json, String code, {String? raw}) async {
        final res = await routes.refuse(s.id, json: json, rawBody: raw);
        expect(res.statusCode, HttpStatus.badRequest, reason: '$json $raw');
        expect(await bodyOf(res), {'error': code}, reason: '$json $raw');
      }

      await refused(null, 'invalid_body', raw: 'nope');
      await refused(null, 'invalid_body', raw: '"photos"');
      await refused({'code': 'rude'}, 'invalid_input');
      await refused(<String, dynamic>{}, 'invalid_input');
      await refused({'code': 'photos', 'note': 42}, 'invalid_input');
      await refused({'code': 'other'}, 'note_required');
      await refused({'code': 'other', 'note': '   '}, 'note_required');
      await refused({'code': 'photos', 'note': 'é' * 501}, 'note_too_long');
      expect((await w.validations.get(s.id))!.state, 'pending');
      expect((await w.audit.list()).total, 0);
    });

    test('404 unknown salon; 409 validation_not_pending (never asked, or '
        'already decided)', () async {
      final gone = await routes.refuse(
        'provider_nope',
        json: {'code': 'photos'},
      );
      expect(gone.statusCode, HttpStatus.notFound);
      expect(await bodyOf(gone), {'error': 'not_found'});

      final never = await w.salon();
      final res = await routes.refuse(never.id, json: {'code': 'photos'});
      expect(res.statusCode, HttpStatus.conflict);
      expect(await bodyOf(res), {'error': 'validation_not_pending'});

      final s = await pending();
      expect(
        (await routes.refuse(s.id, json: {'code': 'photos'})).statusCode,
        HttpStatus.ok,
      );
      final twice = await routes.refuse(s.id, json: {'code': 'photos'});
      expect(twice.statusCode, HttpStatus.conflict);
      expect(await bodyOf(twice), {'error': 'validation_not_pending'});
    });
  });

  group('POST /admin/providers/{id}/restore — « Lever la suspension »', () {
    test('validated, live, offer, owner → 200 {status: active, reason: '
        'null}', () async {
      final s = await live();
      await w.admin.suspend('admin_1', s.id, null);
      final res = await routes.restore(s.id);
      expect(res.statusCode, HttpStatus.ok);
      expect(await bodyOf(res), {'status': 'active', 'reason': null});
      expect(await w.isPublic(s.id), isTrue);
    });

    test('a never-validated draft → 200 {status: draft, reason: '
        'not_validated} — never public', () async {
      final s = await w.salon();
      await w.admin.suspend('admin_1', s.id, null);
      final res = await routes.restore(s.id);
      expect(res.statusCode, HttpStatus.ok);
      expect(await bodyOf(res), {'status': 'draft', 'reason': 'not_validated'});
      expect(await w.isPublic(s.id), isFalse);
    });

    test('NOT suspended → 409 not_suspended (it used to write active over '
        'any salon); unknown → 404', () async {
      final s = await w.salon();
      final res = await routes.restore(s.id);
      expect(res.statusCode, HttpStatus.conflict);
      expect(await bodyOf(res), {'error': 'not_suspended'});
      expect(await w.statusOf(s.id), 'draft');

      final gone = await routes.restore('provider_nope');
      expect(gone.statusCode, HttpStatus.notFound);
      expect(await bodyOf(gone), {'error': 'not_found'});
    });
  });

  group('GET /admin/analytics/overview', () {
    test('providers.pendingValidation = the queue total', () async {
      await pending();
      await pending();
      final res = await routes.overview();
      expect(res.statusCode, HttpStatus.ok);
      final providers = (await bodyOf(res))['providers'] as Map;
      expect(providers['pendingValidation'], 2);
      expect(
        (await bodyOf(await routes.queue(query: 'pageSize=1')))['total'],
        2,
      );
    });
  });

  group('GET /me/provider — `validation` beside the salon', () {
    Future<Map<String, dynamic>> read(({String id, String ownerId}) s) async {
      final res = await routes.meProvider(bearer: owner(s), salonId: s.id);
      expect(res.statusCode, HttpStatus.ok);
      return bodyOf(res);
    }

    test('never asked → the key is there, null; `provider` never carries '
        'it', () async {
      final s = await w.salon();
      final body = await read(s);
      expect(body.keys, containsAll(['account', 'provider', 'membership']));
      expect(body.containsKey('validation'), isTrue);
      expect(body['validation'], isNull);
      expect((body['provider'] as Map).containsKey('validation'), isFalse);
    });

    test('pending → {state, submittedAt, wentLive: false}', () async {
      final s = await pending();
      final v = (await read(s))['validation'] as Map;
      expect(v['state'], 'pending');
      expect(v['wentLive'], isFalse);
      expect(v['submittedAt'], w.now.toIso8601String());
      expect(v.containsKey('offerLive'), isFalse);
      expect(v.containsKey('refusal'), isFalse);
    });

    test('refused → the refusal: code, note, final', () async {
      final s = await pending();
      await w.service.refuse(
        s.id,
        code: 'test_salon',
        note: 'Salon de démonstration.',
        adminId: 'admin_1',
      );
      final v = (await read(s))['validation'] as Map;
      expect(v['state'], 'refused');
      expect(v['refusal'], {
        'code': 'test_salon',
        'note': 'Salon de démonstration.',
        'final': true,
      });
      expect(v['decidedAt'], isNotNull);
      expect(v.containsKey('decidedBy'), isFalse, reason: 'never to a salon');
    });

    test('live → approved, wentLive, no offerLive', () async {
      final s = await live();
      final v = (await read(s))['validation'] as Map;
      expect(v['state'], 'approved');
      expect(v['wentLive'], isTrue);
      expect(v.containsKey('offerLive'), isFalse);
    });

    test('a member who is NOT the owner (a manager) reads the state — never '
        'the admin\'s note, nor whether the offer lapsed', () async {
      final s = await pending();
      await w.service.refuse(
        s.id,
        code: 'other',
        note: 'Envoyez une photo de la façade.',
        adminId: 'admin_1',
      );
      final res = await routes.meProvider(
        bearer: (await managerOf(s.id)).token,
        salonId: s.id,
      );
      expect(res.statusCode, HttpStatus.ok);
      final body = await bodyOf(res);
      expect((body['membership'] as Map)['role'], 'manager');
      expect(body['validation'], {
        'state': 'refused',
        'submittedAt': w.now.toIso8601String(),
        'decidedAt': w.now.toIso8601String(),
        'wentLive': false,
        'refusal': {'code': 'other', 'final': false},
      });
      // The owner, the note's reader, still has it.
      expect(
        (((await read(s))['validation'] as Map)['refusal'] as Map)['note'],
        'Envoyez une photo de la façade.',
      );

      // Validated, not live: billing state is the owner's to read.
      final t = await live();
      await w.providers.setStatus(t.id, 'draft');
      final v =
          (await bodyOf(
                await routes.meProvider(
                  bearer: (await managerOf(t.id)).token,
                  salonId: t.id,
                ),
              ))['validation']
              as Map;
      expect(v['state'], 'approved');
      expect(v['wentLive'], isTrue);
      expect(v.containsKey('offerLive'), isFalse);
      expect(((await read(t))['validation'] as Map)['offerLive'], isTrue);
    });

    test('validated, not live: offerLive tells « Remettre en ligne » from '
        '« impayé »', () async {
      final s = await live();
      await w.providers.setStatus(s.id, 'draft');
      expect(((await read(s))['validation'] as Map)['offerLive'], isTrue);
      w.now = w.now.add(const Duration(days: 200));
      expect(((await read(s))['validation'] as Map)['offerLive'], isFalse);
    });
  });

  group('GET /me/salons — each entry says its validation', () {
    test('a live salon, a waiting one, and one never asked', () async {
      final a = await live();
      final b = await w.salon(name: 'Beauté Zen');
      await w.members.ensureOwner(
        providerId: b.id,
        accountId: a.ownerId,
        email: 'owner@salon.pro',
      );
      final c = await w.salon(name: 'Coiffure Plus');
      await w.members.ensureOwner(
        providerId: c.id,
        accountId: a.ownerId,
        email: 'owner@salon.pro',
      );
      await w.provisioning.publish(b.id);

      final res = await routes.meSalons(bearer: owner(a));
      expect(res.statusCode, HttpStatus.ok);
      final items = ((await bodyOf(res))['items'] as List)
          .cast<Map<String, dynamic>>();
      final byId = {for (final i in items) i['salonId']: i};
      expect((byId[a.id]!['validation'] as Map)['state'], 'approved');
      expect((byId[b.id]!['validation'] as Map)['state'], 'pending');
      expect(byId[c.id]!.containsKey('validation'), isTrue);
      expect(byId[c.id]!['validation'], isNull);
    });

    test('a salon where the caller is a MANAGER: the state, without the '
        'admin\'s note or the offer\'s liveness; the owner\'s rows keep '
        'both', () async {
      final refused = await pending();
      await w.service.refuse(
        refused.id,
        code: 'photos',
        note: 'Ajoutez la devanture.',
        adminId: 'admin_1',
      );
      final offline = await live();
      await w.providers.setStatus(offline.id, 'draft');
      final manager = await managerOf(refused.id);
      final invited = await w.members.invite(
        providerId: offline.id,
        email: 'manager$staffCount@salon.pro',
        role: 'manager',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
      );
      await w.members.activate(invited!.id, manager.accountId);

      final items =
          ((await bodyOf(await routes.meSalons(bearer: manager.token)))['items']
                  as List)
              .cast<Map<String, dynamic>>();
      final byId = {for (final i in items) i['salonId']: i};
      expect(byId[refused.id]!['role'], 'manager');
      expect(byId[refused.id]!['validation'], {
        'state': 'refused',
        'submittedAt': w.now.toIso8601String(),
        'decidedAt': w.now.toIso8601String(),
        'wentLive': false,
        'refusal': {'code': 'photos', 'final': false},
      });
      final v = byId[offline.id]!['validation'] as Map;
      expect(v['state'], 'approved');
      expect(v.containsKey('offerLive'), isFalse);

      // The owners' own lists carry both.
      Future<Map<String, dynamic>> ownRow(
        ({String id, String ownerId}) s,
      ) async {
        final own =
            ((await bodyOf(await routes.meSalons(bearer: owner(s))))['items']
                    as List)
                .cast<Map<String, dynamic>>();
        return own.singleWhere((i) => i['salonId'] == s.id)['validation']
            as Map<String, dynamic>;
      }

      expect(
        ((await ownRow(refused))['refusal'] as Map)['note'],
        'Ajoutez la devanture.',
      );
      expect((await ownRow(offline))['offerLive'], isTrue);
    });
  });
}
