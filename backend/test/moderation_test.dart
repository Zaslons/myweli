import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/admin/moderation_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:myweli_backend/src/reviews_service.dart';
import 'package:test/test.dart';

import '../routes/reviews/[id]/report.dart' as report_route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryReviewsRepository reviews;
  late InMemoryProvidersRepository providers;
  late InMemoryAuditLogRepository audit;
  late ModerationService svc;

  Future<void> seedReview(
    String id, {
    int rating = 5,
    String status = 'visible',
    int day = 1,
  }) => reviews.upsertByAppointment({
    'id': id,
    'appointmentId': 'appt_$id',
    'providerId': 'provider1',
    'userId': 'user_X',
    'userName': 'Client',
    'rating': rating,
    'text': 'ok',
    'verified': true,
    'artistId': null,
    'artistName': null,
    'serviceName': 'Coupe',
    'photoUrls': <String>[],
    'moderationStatus': status,
    'createdAt': DateTime.utc(2026, 6, day).toIso8601String(),
  });

  setUp(() {
    reviews = InMemoryReviewsRepository();
    providers = InMemoryProvidersRepository();
    audit = InMemoryAuditLogRepository();
    final reviewsService = ReviewsService(
      reviews,
      InMemoryAppointmentRepository(),
      providers,
      InMemoryAuthRepository(tokens: tokens, isProd: false),
    );
    svc = ModerationService(reviews, reviewsService, audit);
  });

  test('report is idempotent per user; unknown review → not_found', () async {
    await seedReview('r1');
    expect((await svc.report('u1', 'r1', 'spam')).ok, isTrue);
    await svc.report('u1', 'r1', 'again'); // same user → no new report
    var q = (await svc.queue()).data! as Map;
    expect(q['total'], 1);
    expect((q['items'] as List).first['reportCount'], 1);
    await svc.report('u2', 'r1', 'bad'); // different user → counts
    q = (await svc.queue()).data! as Map;
    expect((q['items'] as List).first['reportCount'], 2);
    expect((await svc.report('u1', 'nope', 'x')).error, 'not_found');
  });

  test('hide removes from feed + rating, resolves reports, audits', () async {
    await seedReview('r1', rating: 5, day: 1);
    await seedReview('r2', rating: 1, day: 2);
    await svc.report('u1', 'r2', 'abusive');
    expect((await reviews.aggregateProvider('provider1')).count, 2);

    final h = await svc.hide('admin_1', 'r2', 'contenu abusif');
    expect(h.ok, isTrue);

    final agg = await reviews.aggregateProvider('provider1');
    expect(agg.count, 1);
    expect(agg.rating, 5); // the 1-star is gone
    expect(
      (await reviews.listForProvider('provider1')).items.map((r) => r['id']),
      ['r1'],
    );
    expect(((await svc.queue()).data! as Map)['total'], 0); // reports resolved
    final log = await audit.list();
    expect(log.items.first['action'], 'review.hide');
    expect(log.items.first['reason'], 'contenu abusif');
  });

  test('dismiss resolves reports but keeps the review visible', () async {
    await seedReview('r1');
    await svc.report('u1', 'r1', 'x');
    final d = await svc.dismissReports('admin_1', 'r1');
    expect(d.ok, isTrue);
    expect(((await svc.queue()).data! as Map)['total'], 0);
    expect((await reviews.listForProvider('provider1')).items.length, 1);
    expect(
      (await audit.list()).items.first['action'],
      'review.dismiss_reports',
    );
  });

  test('restore brings a hidden review back to the feed + rating', () async {
    await seedReview('r1', rating: 4, status: 'hidden');
    expect((await reviews.aggregateProvider('provider1')).count, 0);
    final r = await svc.restore('admin_1', 'r1');
    expect(r.ok, isTrue);
    expect((await reviews.listForProvider('provider1')).items.length, 1);
    expect((await reviews.aggregateProvider('provider1')).count, 1);
    expect((await audit.list()).items.first['action'], 'review.restore');
  });

  test('hiddenQueue lists hidden reviews; restore removes them', () async {
    await seedReview('r1', rating: 5); // visible
    await seedReview('r2', rating: 1, day: 2); // will be hidden
    await svc.hide('admin_1', 'r2', 'abusif');

    var hidden = (await svc.hiddenQueue()).data! as Map;
    expect(hidden['total'], 1);
    expect((hidden['items'] as List).single['id'], 'r2');

    await svc.restore('admin_1', 'r2');
    hidden = (await svc.hiddenQueue()).data! as Map;
    expect(hidden['total'], 0);
  });

  group('report route', () {
    RequestContext ctx({String? bearer, Object body = const {}}) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/reviews/r1/report'),
          headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
          body: jsonEncode(body),
        ),
      );
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<ModerationService>()).thenReturn(svc);
      return c;
    }

    test('consumer 200; provider 403; no token 401', () async {
      await seedReview('r1');
      final userTok = tokens
          .issueAccessToken(subject: 'u1', role: 'user')
          .token;
      final provTok = tokens
          .issueAccessToken(subject: 'acc1', role: 'provider')
          .token;
      expect(
        (await report_route.onRequest(
          ctx(bearer: userTok, body: {'reason': 'spam'}),
          'r1',
        )).statusCode,
        HttpStatus.ok,
      );
      expect(
        (await report_route.onRequest(ctx(bearer: provTok), 'r1')).statusCode,
        HttpStatus.forbidden,
      );
      expect(
        (await report_route.onRequest(ctx(), 'r1')).statusCode,
        HttpStatus.unauthorized,
      );
    });
  });
}
