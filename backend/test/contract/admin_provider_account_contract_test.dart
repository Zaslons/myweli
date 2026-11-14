import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/admin/admin_provider_account_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/demo_seam.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/provider_account_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../routes/admin/_middleware.dart' as admin_mw;
import '../../routes/admin/provider-accounts/[id]/erase.dart' as erase_route;
import '../../routes/admin/provider-accounts/lookup.dart' as lookup_route;
import '../http/observed.dart';
import 'openapi_shape.dart';

class _MockRequestContext extends Mock implements RequestContext {}

/// B0.25's server half, its contract (docs/design/admin-pro-account-erase.md
/// §3, §8 test 16): the document a client — the console screen to come, the
/// website's generated types — is built from says what the two routes
/// answer.
///
/// Two halves, as `salon_validation_contract_test.dart`: the document's
/// codes and request schemas, read from `docs/api/openapi.yaml` and held
/// against the service's own closed set and pattern; then the REAL handlers,
/// every answer checked against the schema the document gives for that path,
/// verb and status ([OpenApiShape], closed objects).
void main() {
  const erasePath = '/admin/provider-accounts/{id}/erase';
  const lookupPath = '/admin/provider-accounts/lookup';

  final yaml = loadYaml(File('../docs/api/openapi.yaml').readAsStringSync());
  final paths = (yaml as YamlMap)['paths'] as YamlMap;
  final schemas = (yaml['components'] as YamlMap)['schemas'] as YamlMap;

  YamlMap op(String path, String method) {
    final item = paths[path];
    expect(item, isA<YamlMap>(), reason: '$path is in the contract');
    final o = (item as YamlMap)[method];
    expect(o, isA<YamlMap>(), reason: '$method $path is in the contract');
    return o as YamlMap;
  }

  String described(String path, String method, String status) {
    final r = (op(path, method)['responses'] as YamlMap)[status];
    expect(r, isA<YamlMap>(), reason: '$method $path documents $status');
    return ((r as YamlMap)['description'] as String?) ?? '';
  }

  YamlMap requestSchema(String path, String method) {
    final body = op(path, method)['requestBody'] as YamlMap?;
    expect(body, isNotNull, reason: '$method $path documents its body');
    expect(body!['required'], isTrue, reason: 'the body is required');
    final ref =
        (((body['content'] as YamlMap)['application/json'] as YamlMap)['schema']
                as YamlMap)[r'$ref']
            as String;
    return schemas[ref.split('/').last] as YamlMap;
  }

  group('the document', () {
    test('erase: DELETE only, admin, every status the route answers, each '
        'code on its own status', () {
      final o = op(erasePath, 'delete');
      expect(o['tags'], ['admin']);
      expect('${o['security']}', contains('bearerAuth'));
      for (final verb in ['get', 'post', 'put', 'patch']) {
        expect((paths[erasePath] as YamlMap)[verb], isNull, reason: verb);
      }
      expect((o['responses'] as YamlMap).keys.toSet(), {
        '204',
        '400',
        '401',
        '403',
        '404',
        '409',
      });
      expect(
        described(erasePath, 'delete', '400'),
        allOf(contains('invalid_body'), contains('invalid_input')),
      );
      expect(
        described(erasePath, 'delete', '403'),
        allOf(contains('`forbidden`'), contains('demo_account_locked')),
      );
      expect(described(erasePath, 'delete', '404'), contains('not_found'));
      expect(
        described(erasePath, 'delete', '409'),
        allOf(contains('confirmation_mismatch'), contains('future_bookings')),
      );
      final description = o['description'] as String;
      expect(description, contains('deleteAccount'));
      expect(description, contains('T83'));
    });

    test('erase body: the three fields required; the reason the SERVICE\'s '
        'closed set; the case number the service\'s pattern', () {
      final s = requestSchema(erasePath, 'delete');
      expect((s['required'] as YamlList).toSet(), {
        'confirmEmail',
        'reason',
        'caseRef',
      });
      final props = s['properties'] as YamlMap;
      expect(props.keys.toSet(), {'confirmEmail', 'reason', 'caseRef'});
      expect(s['additionalProperties'], isFalse);
      expect(
        ((props['reason'] as YamlMap)['enum'] as YamlList).toSet(),
        AdminProviderAccountService.reasons,
      );
      expect(
        (props['caseRef'] as YamlMap)['pattern'],
        AdminProviderAccountService.caseRefPattern.pattern,
      );
    });

    test('lookup: POST only — the address never in a URL — admin, 200 with '
        'the minimal view, 400 with both codes, 404', () {
      final o = op(lookupPath, 'post');
      expect(o['tags'], ['admin']);
      expect('${o['security']}', contains('bearerAuth'));
      expect((paths[lookupPath] as YamlMap)['get'], isNull);
      expect((o['responses'] as YamlMap).keys.toSet(), {
        '200',
        '400',
        '401',
        '403',
        '404',
      });
      expect(
        described(lookupPath, 'post', '400'),
        allOf(contains('invalid_body'), contains('invalid_input')),
      );
      expect(described(lookupPath, 'post', '404'), contains('not_found'));
      final s = requestSchema(lookupPath, 'post');
      expect((s['required'] as YamlList).toList(), ['email']);
      final view = schemas['AdminProviderAccountLookup'] as YamlMap;
      const five = {
        'accountId',
        'email',
        'createdAt',
        'ownedSalons',
        'memberships',
      };
      expect((view['properties'] as YamlMap).keys.toSet(), five);
      // Every one REQUIRED: the procedure reads each, and a field the
      // contract made optional is one a generated client may not expect.
      expect((view['required'] as YamlList).toSet(), five);
    });
  });

  group('the routes answer what the document says', () {
    final tokens = TokenService(secret: 'test-secret');
    final adminToken = tokens
        .issueAccessToken(subject: 'admin_1', role: 'admin')
        .token;
    late InMemoryProviderAuthRepository auth;
    late InMemoryProvidersRepository providers;
    late InMemoryAppointmentRepository appointments;
    late InMemoryMembershipRepository members;
    late AdminProviderAccountService svc;
    final shape = OpenApiShape();

    Map<String, dynamic> salon(String id) => {
      'id': id,
      'slug': 'salon-$id',
      'name': 'Salon $id',
      'status': 'active',
      'phoneNumber': '+2250700000101',
      'address': 'Rue des Jardins, Cocody',
    };

    setUp(() {
      auth = InMemoryProviderAuthRepository(tokens: tokens, echoDevCode: true);
      providers = InMemoryProvidersRepository([
        for (final id in ['s1', 's2', 'sd']) salon(id),
      ]);
      appointments = InMemoryAppointmentRepository();
      members = InMemoryMembershipRepository();
      svc = AdminProviderAccountService(
        ProviderAccountService(
          auth,
          providers,
          appointments,
          FakeStorageService(),
          members,
          client: MockClient((_) async => http.Response('', 204)),
        ),
        auth,
        members,
        providers,
        InMemoryAuditLogRepository(),
      );
    });

    Future<String> account(String email, String salonId) async {
      final reg = await auth.register(
        businessName: 'Salon',
        businessType: 'salon',
        phoneNumber: '+2250700000100',
        email: email,
        authProvider: 'google',
        googleSub: 'sub-$email',
        providerId: salonId,
      );
      await members.ensureOwner(
        providerId: salonId,
        accountId: reg.provider!.id,
        email: email,
      );
      return reg.provider!.id;
    }

    Future<Response> call(
      String method,
      String path,
      Handler route,
      Object? body,
    ) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request(
          method,
          Uri.parse('http://localhost$path'),
          headers: {
            'Authorization': 'Bearer $adminToken',
            'content-type': 'application/json',
          },
          body: body == null ? null : jsonEncode(body),
        ),
      );
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<AdminProviderAccountService>()).thenReturn(svc);
      return observed(admin_mw.middleware(route), c);
    }

    Future<Response> erase(String id, Object? body) => call(
      'DELETE',
      '/admin/provider-accounts/$id/erase',
      (c) => erase_route.onRequest(c, id),
      body,
    );

    Future<Response> lookup(Object? body) => call(
      'POST',
      '/admin/provider-accounts/lookup',
      lookup_route.onRequest,
      body,
    );

    /// [r] has [status], and its body conforms to what the document gives.
    Future<void> conforms(
      Response r,
      String path,
      String method,
      int status,
    ) async {
      expect(r.statusCode, status);
      expect(
        shape.checkResponse(path, method, status, await r.json()),
        isEmpty,
        reason: '$method $path $status',
      );
    }

    test('lookup 200 — with a member row — matches AdminProviderAccountLookup, '
        'closed', () async {
      final id = await account('owner@salon.test', 's1');
      final invite = await members.invite(
        providerId: 's2',
        email: 'owner@salon.test',
        role: 'reception',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
      );
      await members.activate(invite!.id, id);
      await conforms(
        await lookup({'email': 'owner@salon.test'}),
        lookupPath,
        'post',
        200,
      );
    });

    test('lookup 400 and 404 are the Error envelope', () async {
      await conforms(await lookup({'email': 5}), lookupPath, 'post', 400);
      await conforms(await lookup({'email': 'x'}), lookupPath, 'post', 400);
      await conforms(
        await lookup({'email': 'personne@myweli.test'}),
        lookupPath,
        'post',
        404,
      );
    });

    test('erase: 204 is documented with no body; every refusal is the Error '
        'envelope under its documented status', () async {
      Map<String, Object?> body(String email) => {
        'confirmEmail': email,
        'reason': 'support_no_sign_in',
        'caseRef': 'MWP-7K2Q9D',
      };
      final id = await account('owner@salon.test', 's1');
      final demo = await account(kDemoProviderEmail, 'sd');

      await conforms(await erase(id, null), erasePath, 'delete', 400);
      await conforms(
        await erase(id, {...body('owner@salon.test'), 'caseRef': 'x'}),
        erasePath,
        'delete',
        400,
      );
      await conforms(
        await erase(id, body('other@salon.test')),
        erasePath,
        'delete',
        409,
      );
      await conforms(
        await erase(demo, body(kDemoProviderEmail)),
        erasePath,
        'delete',
        403,
      );
      await conforms(
        await erase('nope', body('owner@salon.test')),
        erasePath,
        'delete',
        404,
      );

      final ok = await erase(id, body('owner@salon.test'));
      expect(ok.statusCode, HttpStatus.noContent);
      final documented =
          (op(erasePath, 'delete')['responses'] as YamlMap)['204'] as YamlMap;
      expect(documented['content'], isNull, reason: '204 has no body');
    });
  });
}
