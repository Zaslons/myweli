import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/admin/admin_user_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/clients/clients_repository.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/clients/provider_audit_log.dart';
import 'package:myweli_backend/src/favorites_repository.dart';
import 'package:myweli_backend/src/notifications/notification_prefs_repository.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/privacy/user_erasure_service.dart';
import 'package:myweli_backend/src/push/device_token_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

import '../routes/admin/users/[id]/erase.dart' as erase_route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  registerFallbackValue(Uri.parse('http://localhost'));
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryAuthRepository auth;
  late InMemoryAppointmentRepository appts;
  late InMemoryAuditLogRepository audit;
  late AdminUserService svc;
  late UserErasureService erasure;
  final adminToken = TokenService(
    secret: 'test-secret',
  ).issueAccessToken(subject: 'admin_1', role: 'admin').token;

  Future<String> createUser(String phone) async {
    final req = await auth.requestOtp(phone);
    final v = await auth.verifyOtp(phone, req.devCode!);
    return v.user!.id;
  }

  setUp(() {
    auth = InMemoryAuthRepository(tokens: tokens, echoDevCode: true);
    appts = InMemoryAppointmentRepository();
    audit = InMemoryAuditLogRepository();
    final providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      echoDevCode: true,
    );
    final clients = InMemoryClientsRepository();
    erasure = UserErasureService(
      auth,
      InMemoryDeviceTokenRepository(),
      InMemoryNotificationsRepository(),
      InMemoryNotificationPrefsRepository(),
      InMemoryFavoritesRepository(),
      InMemoryReviewsRepository(),
      appts,
      ClientsService(
        providerAuth,
        MembershipService(InMemoryMembershipRepository(), providerAuth),
        auth,
        clients,
        appts,
        InMemoryProviderAuditLogRepository(),
      ),
      FakeStorageService(),
    );
    svc = AdminUserService(auth, appts, audit, erasure);
  });

  group('DELETE /admin/users/{id}/erase — the route', () {
    RequestContext ctx(String method, String id, {Object? body}) {
      final c = _MockRequestContext();
      final uri = Uri.parse('http://localhost/admin/users/$id/erase');
      when(() => c.request).thenReturn(
        method == 'DELETE'
            ? Request(
                'DELETE',
                uri,
                headers: {
                  'Authorization': 'Bearer $adminToken',
                  if (body != null) 'content-type': 'application/json',
                },
                body: body == null ? null : jsonEncode(body),
              )
            : Request.get(
                uri,
                headers: {'Authorization': 'Bearer $adminToken'},
              ),
      );
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<AdminUserService>()).thenReturn(svc);
      return c;
    }

    test('DELETE → 204; a wrong verb → 405', () async {
      final id = await createUser('+2250700000031');
      expect(
        (await erase_route.onRequest(ctx('DELETE', id), id)).statusCode,
        HttpStatus.noContent,
      );
      // The read-only support view lives one path up; a GET here is a mistake,
      // not an alias for it.
      final other = await createUser('+2250700000032');
      expect(
        (await erase_route.onRequest(ctx('GET', other), other)).statusCode,
        HttpStatus.methodNotAllowed,
      );
      expect(await auth.userById(other), isNotNull);
    });

    test('unknown id → 404', () async {
      final r = await erase_route.onRequest(ctx('DELETE', 'nope'), 'nope');
      expect(r.statusCode, HttpStatus.notFound);
    });

    test('future booking → 409, not 404 — the admin can resolve it', () async {
      final id = await createUser('+2250700000033');
      await appts.create({
        'userId': id,
        'providerId': 'p1',
        'status': 'confirmed',
        'appointmentDate': DateTime.now()
            .toUtc()
            .add(const Duration(days: 3))
            .toIso8601String(),
      });
      final r = await erase_route.onRequest(ctx('DELETE', id), id);
      expect(r.statusCode, HttpStatus.conflict);
      expect(jsonDecode(await r.body())['error'], 'future_bookings');
    });

    test('an absent body is fine — reason is optional', () async {
      final id = await createUser('+2250700000034');
      final r = await erase_route.onRequest(ctx('DELETE', id), id);
      expect(r.statusCode, HttpStatus.noContent);
    });
  });

  group('erase — the admin path to the DELETE /me cascade', () {
    /// **Why this endpoint exists.** An erasure request arrives by e-mail, from
    /// someone who may no longer be able to sign in. Before this, honouring the
    /// privacy policy for that person meant raw SQL against production — which
    /// is exactly how the cascade got missed the first time (`users` deleted,
    /// `device_tokens` left behind, so a deleted user's phone kept ringing).
    test('erases the identity and audits it as user.erase', () async {
      const phone = '+2250700000021';
      final id = await createUser(phone);

      final r = await svc.erase('admin_1', id, 'GDPR request by e-mail');
      expect(r.ok, isTrue);
      expect(await auth.userById(id), isNull, reason: 'identity is gone');

      final entry = (await audit.list()).items.first;
      expect(entry['action'], 'user.erase');
      expect(entry['targetId'], id);
      expect(entry['reason'], 'GDPR request by e-mail');
    });

    test(
      'the audit row carries no PII — it is a tombstone, not a copy',
      () async {
        // The identity is gone, so this row is the only remaining record that the
        // account existed. If it held the phone or e-mail, "erasure" would have
        // moved the data rather than removed it.
        const phone = '+2250700000022';
        final id = await createUser(phone);
        await svc.erase('admin_1', id, null);

        final serialised = (await audit.list()).items.first.toString();
        expect(serialised, contains(id));
        expect(serialised, isNot(contains(phone)));
      },
    );

    test('unknown id → not_found, and nothing is audited', () async {
      final r = await svc.erase('admin_1', 'user_does_not_exist', null);
      expect(r.ok, isFalse);
      expect(r.error, 'not_found');
      expect(
        (await audit.list()).items,
        isEmpty,
        reason:
            'a log line claiming an erasure that did not happen is worse '
            'than no log line',
      );
    });

    test('idempotent — a second erase is not_found, not a crash', () async {
      final id = await createUser('+2250700000023');
      expect((await svc.erase('admin_1', id, null)).ok, isTrue);
      final again = await svc.erase('admin_1', id, null);
      expect(again.ok, isFalse);
      expect(again.error, 'not_found');
    });

    test('refuses while the user holds a future booking', () async {
      // A salon holding a slot for a named person must not be stranded with one
      // it can neither contact nor fill — the same rule DELETE /me enforces.
      // An admin bypass here would make the endpoint the easy way around it.
      final id = await createUser('+2250700000024');
      await appts.create({
        'userId': id,
        'providerId': 'p1',
        'status': 'confirmed',
        'appointmentDate': DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .toIso8601String(),
      });

      final r = await svc.erase('admin_1', id, null);
      expect(r.ok, isFalse);
      expect(r.error, 'future_bookings');
      expect(
        await auth.userById(id),
        isNotNull,
        reason: 'refusal is not a half-erasure',
      );
      expect((await audit.list()).items, isEmpty);
    });
  });

  test('ban blocks login; unban restores it; both audited', () async {
    const phone = '+2250700000001';
    final id = await createUser(phone);

    final r = await svc.ban('admin_1', id, 'abuse');
    expect((r.data! as Map)['status'], 'banned');
    expect((await audit.list()).items.first['action'], 'user.ban');

    // A banned user can't complete login.
    final req = await auth.requestOtp(phone);
    final v = await auth.verifyOtp(phone, req.devCode!);
    expect(v.error, 'account_suspended');

    // Unban → login works again.
    await svc.unban('admin_1', id);
    final req2 = await auth.requestOtp(phone);
    final v2 = await auth.verifyOtp(phone, req2.devCode!);
    expect(v2.ok, isTrue);
  });

  test('list filters by status; detail includes bookings; not_found', () async {
    final id = await createUser('+2250700000002');
    await svc.ban('admin_1', id, 'x');

    final banned = (await svc.list(status: 'banned')).data! as Map;
    expect((banned['items'] as List).length, 1);
    expect((banned['items'] as List).first['status'], 'banned');

    final detail = (await svc.detail(id)).data! as Map;
    expect(detail['id'], id);
    expect(detail.containsKey('recentAppointments'), isTrue);

    expect((await svc.detail('nope')).error, 'not_found');
  });
}
