import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:myweli_backend/src/reviews_service.dart';
import 'package:test/test.dart';

import '../routes/appointments/[id]/review.dart' as review_route;
import '../routes/providers/[id]/reviews/index.dart' as list_route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late InMemoryReviewsRepository reviewsRepo;
  late InMemoryProvidersRepository providers;
  late InMemoryAppointmentRepository appts;
  late ReviewsService service;
  final tokens = TokenService(secret: 'test-secret');
  final accessA = tokens
      .issueAccessToken(subject: 'user_A', role: 'user')
      .token;
  final accessB = tokens
      .issueAccessToken(subject: 'user_B', role: 'user')
      .token;
  final providerTok = tokens
      .issueAccessToken(subject: 'acc1', role: 'provider')
      .token;

  Future<void> seedCompleted(String id, {String userId = 'user_A'}) =>
      appts.create({
        'id': id,
        'userId': userId,
        'providerId': 'provider1',
        'serviceIds': ['service1'],
        'artistId': 'artist1',
        'appointmentDate': DateTime.utc(2030, 6, 10, 9).toIso8601String(),
        'status': 'completed',
        'totalPrice': 15000,
        'depositAmount': 0,
        'balanceDue': 15000,
        'createdAt': DateTime.utc(2030).toIso8601String(),
      });

  setUp(() async {
    reviewsRepo = InMemoryReviewsRepository();
    providers = InMemoryProvidersRepository();
    appts = InMemoryAppointmentRepository();
    service = ReviewsService(
      reviewsRepo,
      appts,
      providers,
      InMemoryAuthRepository(tokens: tokens, isProd: false),
    );
    // Give provider1 an artist so attribution + per-artist recompute is testable.
    (await providers.byId('provider1'))!['artists'] = [
      <String, dynamic>{
        'id': 'artist1',
        'name': 'Awa',
        'providerId': 'provider1',
      },
    ];
  });

  group('InMemoryReviewsRepository', () {
    Map<String, dynamic> r(String appt, {int rating = 5, String? artist}) => {
      'id': 'rev_$appt',
      'appointmentId': appt,
      'providerId': 'provider1',
      'userId': 'u',
      'userName': 'U',
      'rating': rating,
      'text': '',
      'verified': true,
      'artistId': artist,
      'artistName': artist == null ? null : 'A',
      'serviceName': 'Coupe',
      'photoUrls': <String>[],
      'createdAt': '2030-06-1${appt.length}T09:00:00.000Z',
    };

    test('upsert-by-appointment replaces; paginates; aggregates', () async {
      await reviewsRepo.upsertByAppointment(
        r('a', rating: 4, artist: 'artist1'),
      );
      await reviewsRepo.upsertByAppointment(
        r('a', rating: 2, artist: 'artist1'),
      );
      await reviewsRepo.upsertByAppointment(r('bb', rating: 5));

      final page = await reviewsRepo.listForProvider('provider1', pageSize: 1);
      expect(page.total, 2); // 'a' replaced, plus 'bb'
      expect(page.items, hasLength(1)); // page size honoured

      final agg = await reviewsRepo.aggregateProvider('provider1');
      expect(agg.count, 2);
      expect(agg.rating, (2 + 5) / 2);

      final byArtist = await reviewsRepo.aggregateByArtist('provider1');
      expect(byArtist['artist1']!.count, 1);
      expect(byArtist['artist1']!.rating, 2);
    });
  });

  group('ReviewsService', () {
    test(
      'reviews a completed visit: derives fields + recomputes ratings',
      () async {
        await seedCompleted('appt1');
        final res = await service.submitForAppointment(
          'user_A',
          'appt1',
          rating: 5,
          text: 'Super',
        );
        expect(res.ok, isTrue);
        final rev = res.review!;
        expect(rev['verified'], true);
        expect(rev['providerId'], 'provider1');
        expect(rev['artistId'], 'artist1');
        expect(rev['artistName'], 'Awa');
        expect((rev['serviceName'] as String).isNotEmpty, isTrue);

        final p = (await providers.byId('provider1'))!;
        expect(p['rating'], 5);
        expect(p['reviewCount'], 1);
        final artist = (p['artists'] as List).single as Map;
        expect(artist['rating'], 5);
        expect(artist['reviewCount'], 1);
      },
    );

    test('resubmitting the same appointment replaces (count steady)', () async {
      await seedCompleted('appt1');
      await service.submitForAppointment(
        'user_A',
        'appt1',
        rating: 5,
        text: '',
      );
      await service.submitForAppointment(
        'user_A',
        'appt1',
        rating: 1,
        text: '',
      );
      final p = (await providers.byId('provider1'))!;
      expect(p['reviewCount'], 1);
      expect(p['rating'], 1);
    });

    test('gating: non-owner / not-completed / unknown', () async {
      await seedCompleted('appt1'); // user_A's
      expect(
        (await service.submitForAppointment(
          'user_B',
          'appt1',
          rating: 5,
          text: '',
        )).error,
        'forbidden',
      );
      await appts.create({
        'id': 'pending1',
        'userId': 'user_A',
        'providerId': 'provider1',
        'serviceIds': ['service1'],
        'artistId': null,
        'appointmentDate': DateTime.utc(2030, 7, 1, 9).toIso8601String(),
        'status': 'pending',
        'totalPrice': 15000,
        'depositAmount': 0,
        'balanceDue': 15000,
        'createdAt': DateTime.utc(2030).toIso8601String(),
      });
      expect(
        (await service.submitForAppointment(
          'user_A',
          'pending1',
          rating: 5,
          text: '',
        )).error,
        'not_completed',
      );
      expect(
        (await service.submitForAppointment(
          'user_A',
          'nope',
          rating: 5,
          text: '',
        )).error,
        'not_found',
      );
    });

    test('rejects bad rating / over-long text / too many photos', () async {
      await seedCompleted('appt1');
      Future<String?> err({
        Object? rating,
        Object? text,
        Object? photos,
      }) async => (await service.submitForAppointment(
        'user_A',
        'appt1',
        rating: rating ?? 5,
        text: text ?? '',
        photoUrls: photos,
      )).error;
      expect(await err(rating: 0), 'invalid_input');
      expect(await err(rating: 6), 'invalid_input');
      expect(await err(text: 'x' * 1001), 'invalid_input');
      expect(
        await err(photos: List.generate(7, (i) => 'u$i')),
        'invalid_input',
      );
    });
  });

  group('routes', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<ReviewsService>()).thenReturn(service);
      return context;
    }

    Request post(String path, {String? bearer, Object? body}) => Request.post(
      Uri.parse('http://localhost$path'),
      headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
      body: body == null ? null : '{"rating":5,"text":"ok"}',
    );

    test('POST → 201; provider token → 403; no token → 401; GET → 200; '
        'bad verb → 405', () async {
      await seedCompleted('appt1');

      final ok = await review_route.onRequest(
        ctx(post('/appointments/appt1/review', bearer: accessA, body: {})),
        'appt1',
      );
      expect(ok.statusCode, HttpStatus.created);

      // Not the owner → 403.
      final notOwner = await review_route.onRequest(
        ctx(post('/appointments/appt1/review', bearer: accessB, body: {})),
        'appt1',
      );
      expect(notOwner.statusCode, HttpStatus.forbidden);

      // Provider token → 403.
      final asProvider = await review_route.onRequest(
        ctx(post('/appointments/appt1/review', bearer: providerTok, body: {})),
        'appt1',
      );
      expect(asProvider.statusCode, HttpStatus.forbidden);

      // No token → 401.
      final noAuth = await review_route.onRequest(
        ctx(post('/appointments/appt1/review', body: {})),
        'appt1',
      );
      expect(noAuth.statusCode, HttpStatus.unauthorized);

      // Public paginated list.
      final list = await list_route.onRequest(
        ctx(
          Request.get(
            Uri.parse('http://localhost/providers/provider1/reviews'),
          ),
        ),
        'provider1',
      );
      expect(list.statusCode, HttpStatus.ok);
      expect((await list.json() as Map)['total'], 1);

      // Bad verb on the list.
      final badVerb = await list_route.onRequest(
        ctx(
          Request.post(
            Uri.parse('http://localhost/providers/provider1/reviews'),
          ),
        ),
        'provider1',
      );
      expect(badVerb.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
