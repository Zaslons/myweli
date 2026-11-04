import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/admin/moderation_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:myweli_backend/src/reviews_service.dart';
import 'package:test/test.dart';

import '../routes/me/provider/reviews/[id]/report.dart' as report_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockProviderAuth extends Mock implements ProviderAuthRepository {}

ProviderAccount _account(String id, {String? providerId}) => ProviderAccount(
  id: id,
  phoneNumber: '+2250700000009',
  businessName: 'Salon Awa',
  businessType: 'salon',
  createdAt: DateTime.utc(2026),
)..providerId = providerId;

/// docs/design/backend-integrity-batch6.md §2.6 (B6.6, decision 20) — a salon
/// reports a review of ITS salon: App Store 1.2 expects a way to report user
/// content, and the Pro « Avis » had none. The same admin queue as a client's
/// report, marked « Signalé par le salon »; Propriétaire and Gérant only
/// (`profile.manage`); idempotent per review and salon.
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late _MockProviderAuth auth;
  late InMemoryMembershipRepository memberships;
  late InMemoryReviewsRepository reviews;

  setUp(() async {
    auth = _MockProviderAuth();
    memberships = InMemoryMembershipRepository();
    reviews = InMemoryReviewsRepository();
    when(() => auth.accountById(any())).thenAnswer(
      (i) async => _account(
        i.positionalArguments.first as String,
        providerId: i.positionalArguments.first == 'owner' ? 'p1' : null,
      ),
    );
    await memberships.ensureOwner(
      providerId: 'p1',
      accountId: 'owner',
      email: 'owner@salon.ci',
    );
    for (final (id, role) in [
      ('manager', 'manager'),
      ('reception', 'reception'),
      ('staff', 'staff'),
    ]) {
      final inv = await memberships.invite(
        providerId: 'p1',
        email: '$id@salon.ci',
        role: role,
        artistId: role == 'staff' ? 'a1' : null,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      await memberships.activate(inv!.id, id);
    }
    for (final (id, salon) in [('r1', 'p1'), ('r2', 'p2')]) {
      await reviews.upsertByAppointment({
        'id': id,
        'appointmentId': 'a-$id',
        'providerId': salon,
        'userId': 'u1',
        'userName': 'Awa',
        'rating': 1,
        'text': 'Injurieux',
        'createdAt': DateTime.utc(2026).toIso8601String(),
      });
    }
  });

  RequestContext ctx(Request request) {
    final c = _MockRequestContext();
    when(() => c.request).thenReturn(request);
    when(() => c.read<TokenService>()).thenReturn(tokens);
    when(() => c.read<ProviderAuthRepository>()).thenReturn(auth);
    when(
      () => c.read<MembershipService>(),
    ).thenReturn(MembershipService(memberships, auth));
    when(() => c.read<ModerationService>()).thenReturn(
      ModerationService(
        reviews,
        ReviewsService(
          reviews,
          InMemoryAppointmentRepository(),
          InMemoryProvidersRepository(),
          InMemoryAuthRepository(tokens: tokens, echoDevCode: true),
        ),
        InMemoryAuditLogRepository(),
      ),
    );
    return c;
  }

  Future<Response> report(
    String reviewId, {
    String? as,
    String role = 'provider',
    String method = 'POST',
    Object? body,
  }) => report_route.onRequest(
    ctx(
      Request(
        method,
        Uri.parse('http://localhost/me/provider/reviews/$reviewId/report'),
        headers: as == null
            ? null
            : {
                'Authorization':
                    'Bearer ${tokens.issueAccessToken(subject: as, role: role).token}',
              },
        body: body == null ? null : jsonEncode(body),
      ),
    ),
    reviewId,
  );

  Future<List<Map<String, dynamic>>> queue() async =>
      (await reviews.listReportedReviews()).items;

  test('the owner reports a review of the salon → 200, in the queue, marked '
      '« by the salon »', () async {
    final res = await report('r1', as: 'owner', body: {'reason': 'Insultes'});
    expect(res.statusCode, HttpStatus.ok);
    expect(await res.json(), {'status': 'reported'});
    final q = await queue();
    expect(q.single['reviewId'], 'r1');
    expect(q.single['reportedBySalon'], isTrue);
    expect(q.single['lastReason'], 'Insultes');
  });

  test('the Gérant may too; no reason is a report all the same', () async {
    expect((await report('r1', as: 'manager')).statusCode, HttpStatus.ok);
    expect((await queue()).single['reportCount'], 1);
  });

  for (final role in ['reception', 'staff']) {
    test(
      '$role → 403, nothing recorded (Propriétaire and Gérant only)',
      () async {
        final res = await report('r1', as: role);
        expect(res.statusCode, HttpStatus.forbidden);
        expect(await queue(), isEmpty);
      },
    );
  }

  test('a review of ANOTHER salon → 404, nothing recorded', () async {
    final res = await report('r2', as: 'owner');
    expect(res.statusCode, HttpStatus.notFound);
    expect(await queue(), isEmpty);
  });

  test('twice → one report (idempotent per review and salon)', () async {
    await report('r1', as: 'owner');
    await report('r1', as: 'manager');
    expect((await queue()).single['reportCount'], 1);
  });

  test('a client’s report beside it: two reports, still marked', () async {
    await reviews.addReport('r1', 'user_1', 'spam');
    await report('r1', as: 'owner');
    final q = await queue();
    expect(q.single['reportCount'], 2);
    expect(q.single['reportedBySalon'], isTrue);
  });

  test('the salon first, a client after: still marked', () async {
    await report('r1', as: 'owner');
    // The queue reads the newest report first — here the client's, so the
    // mark has to survive a report that is not the salon's.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await reviews.addReport('r1', 'user_1', 'spam');
    final q = await queue();
    expect(q.single['reportCount'], 2);
    expect(q.single['reportedBySalon'], isTrue);
  });

  test('CONTROL — a client’s report alone is not marked', () async {
    await reviews.addReport('r1', 'user_1', 'spam');
    expect((await queue()).single['reportedBySalon'], isFalse);
  });

  test('a reason over 500 characters → 400 invalid_input', () async {
    final res = await report('r1', as: 'owner', body: {'reason': 'x' * 501});
    expect(res.statusCode, HttpStatus.badRequest);
    expect((await res.json() as Map)['error'], 'invalid_input');
  });

  test('a client token → 403 · no token → 401 · GET → 405', () async {
    expect(
      (await report('r1', as: 'u1', role: 'user')).statusCode,
      HttpStatus.forbidden,
    );
    expect((await report('r1')).statusCode, HttpStatus.unauthorized);
    expect(
      (await report('r1', as: 'owner', method: 'GET')).statusCode,
      HttpStatus.methodNotAllowed,
    );
    expect(await queue(), isEmpty);
  });

  test(
    'a client token naming a salon member → 403, nothing recorded',
    () async {
      // The role is read first: a `user` token is a client's, whatever its
      // subject — even the id of the salon's Propriétaire.
      final res = await report('r1', as: 'owner', role: 'user');
      expect(res.statusCode, HttpStatus.forbidden);
      expect(await queue(), isEmpty);
    },
  );

  test('not a member of any salon → 403', () async {
    final res = await report('r1', as: 'stranger');
    expect(res.statusCode, HttpStatus.forbidden);
  });
}
