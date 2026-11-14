import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/admin/admin_provider_account_service.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:myweli_backend/src/db/postgres_appointment_repository.dart';
import 'package:myweli_backend/src/db/postgres_audit_log_repository.dart';
import 'package:myweli_backend/src/db/postgres_device_token_repository.dart';
import 'package:myweli_backend/src/db/postgres_membership_repository.dart';
import 'package:myweli_backend/src/db/postgres_notifications_repository.dart';
import 'package:myweli_backend/src/db/postgres_provider_auth_repository.dart';
import 'package:myweli_backend/src/db/postgres_providers_repository.dart';
import 'package:myweli_backend/src/db/postgres_salon_place_notice_repository.dart';
import 'package:myweli_backend/src/db/postgres_salon_validation_repository.dart';
import 'package:myweli_backend/src/provider_account_service.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/admin/_middleware.dart' as admin_mw;
import '../../routes/admin/provider-accounts/[id]/erase.dart' as erase_route;
import '../../routes/admin/provider-accounts/lookup.dart' as lookup_route;
import '../http/observed.dart';

class _MockRequestContext extends Mock implements RequestContext {}

/// The support erase of a Pro account on the REAL schema
/// (docs/design/admin-pro-account-erase.md §8, test 15).
///
/// Every in-memory test of a deletion ran on twins with no foreign keys, and
/// production answered 500 to every salon owner's `DELETE /me/provider` for
/// that reason (2026-10-14, docs/design/backend-provider-deletion-member-fk.md).
/// So the admin path is driven here through its routes, the `/admin` gate and
/// the outermost middleware, over Postgres: 0038's cascade included, the
/// audit row read back from `audit_log`.
void main() {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    test(
      'postgres admin provider-account erase (skipped — set DATABASE_URL '
      'to run)',
      () {},
      skip: 'requires DATABASE_URL',
    );
    return;
  }

  late Pool<void> pool;
  final tokens = TokenService(secret: 'test-secret');
  final adminToken = tokens
      .issueAccessToken(subject: 'admin_pg', role: 'admin')
      .token;

  setUpAll(() async {
    pool = createPool(url);
    await withSchemaLock(pool, () => runMigrations(pool));
  });

  tearDownAll(() async => pool.close());

  PostgresProviderAuthRepository authRepo() =>
      PostgresProviderAuthRepository(pool, tokens: tokens, echoDevCode: true);

  /// The production wiring of `dependencies.dart`, as far as a test can hold
  /// it: the repositories `deleteAccount` writes through, on the database.
  AdminProviderAccountService service() {
    final accounts = ProviderAccountService(
      authRepo(),
      PostgresProvidersRepository(pool),
      PostgresAppointmentRepository(pool),
      FakeStorageService(),
      PostgresMembershipRepository(pool),
      devices: PostgresDeviceTokenRepository(pool),
      notifications: PostgresNotificationsRepository(pool),
      validations: PostgresSalonValidationRepository(pool),
      placeNotices: PostgresSalonPlaceNoticeRepository(pool),
      client: MockClient((_) async => http.Response('', 204)),
    );
    return AdminProviderAccountService(
      accounts,
      authRepo(),
      PostgresMembershipRepository(pool),
      PostgresProvidersRepository(pool),
      PostgresAuditLogRepository(pool),
    );
  }

  Future<int> count(String sql, Map<String, Object?> parameters) async {
    final r = await pool.execute(Sql.named(sql), parameters: parameters);
    return r.first.first! as int;
  }

  /// A fresh suffix per run: the suite is re-runnable against one database.
  final run = DateTime.now().microsecondsSinceEpoch;

  /// An owner as production makes one: a salon, the account linked to it,
  /// the owner row (`SalonProvisioningService.ensureSalon`).
  Future<({String id, String email, String salonId})> owner(
    String tag,
    String phone,
  ) async {
    final email = 'r1-$tag-$run@test.pro';
    final salon = await PostgresProvidersRepository(pool).createSalon(
      name: 'Salon R1 $tag $run',
      category: 'salon',
      phoneNumber: phone,
    );
    final salonId = salon['id'] as String;
    final reg = await authRepo().register(
      email: email,
      authProvider: 'google',
      googleSub: 'sub-$email',
      phoneNumber: phone,
      businessName: 'Salon',
      businessType: 'salon',
      providerId: salonId,
    );
    final id = reg.provider!.id;
    await PostgresMembershipRepository(
      pool,
    ).ensureOwner(providerId: salonId, accountId: id, email: email);
    return (id: id, email: email, salonId: salonId);
  }

  RequestContext ctx(
    String method,
    String path,
    Object body,
    AdminProviderAccountService svc,
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
        body: jsonEncode(body),
      ),
    );
    when(() => c.read<TokenService>()).thenReturn(tokens);
    when(() => c.read<AdminProviderAccountService>()).thenReturn(svc);
    return c;
  }

  test('lookup, then erase through the route: 204, the identity and its '
      'membership rows gone (0038), the salon hidden and wiped, a teammate '
      'kept, one audit row with no e-mail', () async {
    final svc = service();
    final providers = PostgresProvidersRepository(pool);
    final members = PostgresMembershipRepository(pool);

    final o = await owner('owner', '+2250500008301');
    await providers.setStatus(o.salonId, 'active');
    await providers.updateProfile(o.salonId, {
      'address': 'Rue des Jardins, Cocody',
      'whatsapp': '+2250500008302',
    });

    // A teammate in the owner's salon — their row must survive.
    final mate = await owner('mate', '+2250500008303');
    final invite = await members.invite(
      providerId: o.salonId,
      email: mate.email,
      role: 'manager',
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    );
    await members.activate(invite!.id, mate.id);

    // The lookup names the salon the erase will hide.
    final found = await observed(
      admin_mw.middleware(lookup_route.onRequest),
      ctx('POST', '/admin/provider-accounts/lookup', {
        'email': o.email.toUpperCase(),
      }, svc),
    );
    expect(found.statusCode, HttpStatus.ok);
    final view = await found.json() as Map<String, dynamic>;
    expect(view['accountId'], o.id);
    expect(view['email'], o.email);
    expect(
      [for (final s in view['ownedSalons'] as List) (s as Map)['id']],
      [o.salonId],
    );

    final caseRef = 'MWP-${(run % 1000000).toString().padLeft(6, '0')}';
    Future<Response> erase() => observed(
      admin_mw.middleware((c) => erase_route.onRequest(c, o.id)),
      ctx('DELETE', '/admin/provider-accounts/${o.id}/erase', {
        'confirmEmail': o.email,
        'reason': 'support_no_sign_in',
        'caseRef': caseRef,
      }, svc),
    );

    final r = await erase();
    expect(r.statusCode, HttpStatus.noContent, reason: await r.body());

    expect(await authRepo().accountById(o.id), isNull);
    expect(
      await count(
        'SELECT count(*)::int FROM provider_members WHERE account_id = @a',
        {'a': o.id},
      ),
      0,
      reason: 'the account’s rows go with the identity',
    );
    expect(
      await count(
        'SELECT count(*)::int FROM provider_members '
        'WHERE account_id = @a AND provider_id = @p',
        {'a': mate.id, 'p': o.salonId},
      ),
      1,
      reason: 'the teammate stays',
    );
    final doc = (await providers.byId(o.salonId))!;
    expect(doc['status'], 'draft');
    expect(doc['phoneNumber'], '');
    expect(doc['address'], '');
    expect(doc['whatsapp'], isNull);

    final rows = (await PostgresAuditLogRepository(
      pool,
    ).list(action: 'provider_account.erase', pageSize: 100)).items;
    final mine = [
      for (final row in rows)
        if (row['targetId'] == o.id) row,
    ];
    expect(mine, hasLength(1));
    expect(mine.single['actorAdminId'], 'admin_pg');
    expect(mine.single['reason'], 'support_no_sign_in');
    expect(mine.single['metadata'], {'caseRef': caseRef});
    expect(jsonEncode(mine.single), isNot(contains(o.email)));

    // The repeat: 404, and still one row.
    final again = await erase();
    expect(again.statusCode, HttpStatus.notFound);
    final after = (await PostgresAuditLogRepository(
      pool,
    ).list(action: 'provider_account.erase', pageSize: 100)).items;
    expect(after.where((row) => row['targetId'] == o.id), hasLength(1));
  });
}
