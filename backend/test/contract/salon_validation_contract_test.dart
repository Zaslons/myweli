import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../validation/validation_routes_harness.dart';
import '../validation/validation_world.dart';
import 'openapi_shape.dart';

/// B0.18's contract (docs/design/salon-go-live-approval.md §3.5, §3.8):
/// the document a client is generated from says what the routes answer.
///
/// Two halves. The first reads `docs/api/openapi.yaml` the way the other
/// contract tests do — the codes each route documents, the sentences that
/// moved. The second drives the REAL handlers over the in-memory world and
/// checks every answer against the schema the document gives for that
/// path, verb and status ([OpenApiShape], closed objects): a field the
/// server sends and the contract does not name, a required one it forgets,
/// a wrong type, a value outside an enum — each is a failure here, not a
/// surprise in a generated client.
void main() {
  final yaml = loadYaml(File('../docs/api/openapi.yaml').readAsStringSync());
  final paths = (yaml as YamlMap)['paths'] as YamlMap;
  final schemas = (yaml['components'] as YamlMap)['schemas'] as YamlMap;

  YamlMap op(String path, String method) =>
      (paths[path] as YamlMap)[method] as YamlMap;

  String described(String path, String method, String status) {
    final r = (op(path, method)['responses'] as YamlMap)[status];
    expect(r, isA<YamlMap>(), reason: '$method $path documents $status');
    return ((r as YamlMap)['description'] as String?) ?? '';
  }

  group('the document', () {
    test('publish: a REQUEST — 202 with the validation, no trial here', () {
      final description =
          op('/providers/{id}/publish', 'post')['description'] as String;
      expect(description, contains('A request, not a publication'));
      expect(description, contains('No trial starts here'));
      expect(
        described('/providers/{id}/publish', 'post', '202'),
        contains('stays `draft`'),
      );
      final conflict = described('/providers/{id}/publish', 'post', '409');
      expect(conflict, contains('incomplete'));
      expect(conflict, contains('validation_refused_final'));
    });

    test('« the trial starts at the first publish » is gone from the whole '
        'contract', () {
      final text = File('../docs/api/openapi.yaml').readAsStringSync();
      for (final stale in [
        'first publish',
        'The trial starts here',
        'owner publishes',
        'gets its trial at this publish',
      ]) {
        expect(text, isNot(contains(stale)), reason: stale);
      }
    });

    test('…and each place it stood now names MyWeli\'s validation', () {
      expect(
        described('/providers/{id}/subscription', 'get', '404'),
        contains("MyWeli's validation"),
      );
      expect(
        op('/providers/{id}/subscription', 'put')['description'],
        contains('the validation already did'),
      );
      expect(
        op('/me/salons', 'post')['description'],
        contains('MyWeli validates it'),
      );
      expect(
        op('/auth/provider/register', 'post')['description'],
        contains('MyWeli validates it'),
      );
    });

    test('§3.8: every new code is documented on the route that answers '
        'it', () {
      const approve = '/admin/salons/{id}/validation/approve';
      const refuse = '/admin/salons/{id}/validation/refuse';
      final approveConflict = described(approve, 'post', '409');
      for (final code in [
        'provider_suspended',
        'incomplete',
        'missing',
        'validation_not_pending',
        'no_owner',
        'invalid_state',
      ]) {
        expect(approveConflict, contains(code), reason: code);
      }
      expect(
        described(approve, 'post', '400'),
        allOf(contains('invalid_body'), contains('invalid_input')),
      );
      final refuseBad = described(refuse, 'post', '400');
      for (final code in [
        'invalid_body',
        'invalid_input',
        'note_required',
        'note_too_long',
      ]) {
        expect(refuseBad, contains(code), reason: code);
      }
      expect(
        described(refuse, 'post', '409'),
        contains('validation_not_pending'),
      );
      expect(
        described('/admin/providers/{id}/restore', 'post', '409'),
        contains('not_suspended'),
      );
    });

    test('the validation travels BESIDE the salon: /me/provider and '
        'SalonMembership carry it; Provider — the public schema — does '
        'not', () {
      final meProvider =
          (((op('/me/provider', 'get')['responses'] as YamlMap)['200']
                      as YamlMap)['content']
                  as YamlMap)['application/json']
              as YamlMap;
      final props =
          ((meProvider['schema'] as YamlMap)['properties'] as YamlMap);
      expect('${props['validation']}', contains('SalonValidation'));
      expect(
        '${((schemas['SalonMembership'] as YamlMap)['properties'] as YamlMap)['validation']}',
        contains('SalonValidation'),
      );
      expect(
        ((schemas['Provider'] as YamlMap)['properties'] as YamlMap).containsKey(
          'validation',
        ),
        isFalse,
      );
    });

    test('the refusal codes are §4.3\'s closed list, the same in the schema '
        'and in refuse\'s body', () {
      const codes = [
        'incomplete_info',
        'photos',
        'unconfirmed',
        'outside_ci',
        'test_salon',
        'other',
      ];
      final refusal =
          (((schemas['SalonValidation'] as YamlMap)['properties']
                      as YamlMap)['refusal']
                  as YamlMap)['properties']
              as YamlMap;
      expect((refusal['code'] as YamlMap)['enum'], codes);
      final body =
          (((op('/admin/salons/{id}/validation/refuse', 'post')['requestBody']
                          as YamlMap)['content']
                      as YamlMap)['application/json']
                  as YamlMap)['schema']
              as YamlMap;
      expect(
        (((body['properties'] as YamlMap)['code']) as YamlMap)['enum'],
        codes,
      );
    });
  });

  group('the answers match the document', () {
    late ValidationWorld w;
    late ValidationRoutes routes;
    final shape = OpenApiShape();

    setUp(() {
      w = ValidationWorld();
      routes = ValidationRoutes(w);
    });

    /// [res] has the [status] the test expects, and its body is what the
    /// contract documents for [method] [path] at that status.
    Future<Map<String, dynamic>> conforms(
      Response res,
      String path,
      String method,
      int status,
    ) async {
      expect(res.statusCode, status, reason: '$method $path');
      final body = await bodyOf(res);
      expect(
        shape.checkResponse(path, method, status, body),
        isEmpty,
        reason: '$method $path $status: $body',
      );
      return body;
    }

    Future<({String id, String ownerId})> pending({
      String name = 'Salon Awa',
    }) async {
      final s = await w.salon(name: name);
      expect((await w.provisioning.publish(s.id)).accepted, isTrue);
      return s;
    }

    String owner(({String id, String ownerId}) s) =>
        routes.token(s.ownerId, 'provider');

    test('the checker can fail: a wrong type, a missing key, an unnamed '
        'key, a value outside the enum', () {
      final schema = shape.responseSchema(
        '/providers/{id}/publish',
        'post',
        202,
      );
      expect(shape.check({'validation': null}, schema), isEmpty);
      expect(
        shape.check({
          'validation': {'state': 'live', 'wentLive': 'yes', 'extra': 1},
        }, schema),
        hasLength(3),
      );
      expect(shape.check(<String, dynamic>{}, schema), hasLength(1));
      expect(
        shape.check({
          'validation': {
            'state': 'refused',
            'wentLive': false,
            'refusal': {'code': 'other', 'note': 'é' * 501, 'final': false},
          },
        }, schema),
        hasLength(1),
      );
    });

    test('publish: 202, 200, the 409s, a 403', () async {
      const path = '/providers/{id}/publish';
      final s = await w.salon();
      await conforms(
        await routes.publish(s.id, bearer: owner(s)),
        path,
        'post',
        202,
      );
      await w.service.approve(s.id, from: 'pending', adminId: 'admin_1');
      await conforms(
        await routes.publish(s.id, bearer: owner(s)),
        path,
        'post',
        200,
      );

      final incomplete = await w.salon(complete: false);
      await conforms(
        await routes.publish(incomplete.id, bearer: owner(incomplete)),
        path,
        'post',
        409,
      );

      final refused = await pending();
      await w.service.refuse(
        refused.id,
        code: 'test_salon',
        note: null,
        adminId: 'admin_1',
      );
      await conforms(
        await routes.publish(refused.id, bearer: owner(refused)),
        path,
        'post',
        409,
      );

      await w.providers.setStatus(incomplete.id, 'suspended');
      await conforms(
        await routes.publish(incomplete.id, bearer: owner(incomplete)),
        path,
        'post',
        403,
      );
    });

    test('the queue: each tab, and its 400', () async {
      const path = '/admin/salon-validations';
      final a = await pending();
      final b = await pending(name: 'Salon B');
      await w.service.refuse(
        b.id,
        code: 'other',
        note: 'Une précision.',
        adminId: 'admin_1',
      );
      final c = await pending(name: 'Salon C');
      await w.service.approve(c.id, from: 'pending', adminId: 'admin_1');
      for (final state in ['pending', 'refused', 'approved']) {
        final body = await conforms(
          await routes.queue(query: 'state=$state'),
          path,
          'get',
          200,
        );
        expect(body['items'], isNotEmpty, reason: state);
      }
      expect(a.id, isNotEmpty);
      await conforms(await routes.queue(query: 'state=nope'), path, 'get', 400);
    });

    test('the detail: never asked, pending, refused, validated with its '
        'offer; 404', () async {
      const path = '/admin/salons/{id}/validation';
      final never = await w.salon();
      await conforms(await routes.detail(never.id), path, 'get', 200);
      final p = await pending();
      await conforms(await routes.detail(p.id), path, 'get', 200);
      await w.service.refuse(
        p.id,
        code: 'other',
        note: 'Une précision.',
        adminId: 'admin_1',
      );
      await conforms(await routes.detail(p.id), path, 'get', 200);
      final live = await w.salon();
      await w.validateLive(live.id);
      final body = await conforms(
        await routes.detail(live.id),
        path,
        'get',
        200,
      );
      expect(body['offer'], isNotNull);
      await conforms(await routes.detail('provider_nope'), path, 'get', 404);
    });

    test('approve: 200, 400, 404, the 409 with missing and without', () async {
      const path = '/admin/salons/{id}/validation/approve';
      final s = await pending();
      await conforms(
        await routes.approve(s.id, json: {'from': 'nope'}),
        path,
        'post',
        400,
      );
      final incomplete = await pending();
      await w.providers.updateProfile(incomplete.id, {'imageUrls': <String>[]});
      await conforms(
        await routes.approve(incomplete.id, json: {'from': 'pending'}),
        path,
        'post',
        409,
      );
      await conforms(
        await routes.approve(s.id, json: {'from': 'pending'}),
        path,
        'post',
        200,
      );
      await conforms(
        await routes.approve(s.id, json: {'from': 'pending'}),
        path,
        'post',
        409,
      );
      await conforms(
        await routes.approve('provider_nope', json: {'from': 'pending'}),
        path,
        'post',
        404,
      );
    });

    test('refuse: 200 (with and without a note), 400, 409, 404', () async {
      const path = '/admin/salons/{id}/validation/refuse';
      final a = await pending();
      await conforms(
        await routes.refuse(a.id, json: {'code': 'other'}),
        path,
        'post',
        400,
      );
      await conforms(
        await routes.refuse(a.id, json: {'code': 'outside_ci'}),
        path,
        'post',
        200,
      );
      final b = await pending();
      await conforms(
        await routes.refuse(b.id, json: {'code': 'other', 'note': 'Voir.'}),
        path,
        'post',
        200,
      );
      await conforms(
        await routes.refuse(b.id, json: {'code': 'photos'}),
        path,
        'post',
        409,
      );
      await conforms(
        await routes.refuse('provider_nope', json: {'code': 'photos'}),
        path,
        'post',
        404,
      );
    });

    test('restore: 200 active, 200 draft with its reason, 409', () async {
      const path = '/admin/providers/{id}/restore';
      final live = await w.salon();
      await w.validateLive(live.id);
      await w.admin.suspend('admin_1', live.id, null);
      await conforms(await routes.restore(live.id), path, 'post', 200);
      final draft = await w.salon();
      await w.admin.suspend('admin_1', draft.id, null);
      final body = await conforms(
        await routes.restore(draft.id),
        path,
        'post',
        200,
      );
      expect(body['reason'], 'not_validated');
      await conforms(await routes.restore(draft.id), path, 'post', 409);
    });

    test('the overview', () async {
      await pending();
      final body = await conforms(
        await routes.overview(),
        '/admin/analytics/overview',
        'get',
        200,
      );
      expect((body['providers'] as Map)['pendingValidation'], 1);
    });

    test('/me/provider in every validation state, and /me/salons', () async {
      final s = await w.salon();
      Future<void> read() async {
        final res = await routes.meProvider(bearer: owner(s), salonId: s.id);
        await conforms(res, '/me/provider', 'get', 200);
        await conforms(
          await routes.meSalons(bearer: owner(s)),
          '/me/salons',
          'get',
          200,
        );
      }

      await read(); // never asked
      await w.provisioning.publish(s.id);
      await read(); // pending
      await w.service.refuse(
        s.id,
        code: 'other',
        note: 'Une précision.',
        adminId: 'admin_1',
      );
      await read(); // refused
      await w.provisioning.publish(s.id);
      await w.service.approve(s.id, from: 'pending', adminId: 'admin_1');
      await read(); // live
      await w.providers.setStatus(s.id, 'draft');
      await read(); // validated, not live: offerLive
    });
  });
}
