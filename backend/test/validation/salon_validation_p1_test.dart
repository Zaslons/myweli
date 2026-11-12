import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_lifecycle_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/favorites_repository.dart';
import 'package:myweli_backend/src/favorites_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:test/test.dart';

import '../../routes/availability/index.dart' as availability_route;
import '../../routes/me/favorites/[providerId].dart' as favorite_route;
import '../../routes/me/favorites/index.dart' as favorites_route;
import '../../routes/providers/[id]/index.dart' as provider_route;
import '../../routes/providers/by-slug/[slug].dart' as by_slug_route;
import '../../routes/providers/index.dart' as providers_route;
import '../../routes/sitemap/providers.dart' as sitemap_route;
import 'validation_routes_harness.dart' show bodyOf;
import 'validation_world.dart';

class _MockRequestContext extends Mock implements RequestContext {}

/// A catalogue the slot engine can read (priced services, ISO hours), on
/// every fixture alike — so a hidden salon is refused for its state alone,
/// and the live one is genuinely bookable.
final Map<String, dynamic> _bookable = {
  'services': [
    for (final id in ['s1', 's2', 's3'])
      {
        'id': id,
        'name': 'Prestation $id',
        'price': 5000,
        'durationMinutes': 30,
        'active': true,
      },
  ],
  'availability': {
    'weeklySchedule': {
      for (var d = 0; d < 7; d++)
        '$d': [
          {
            'startTime': DateTime.utc(2024, 1, 1, 9).toIso8601String(),
            'endTime': DateTime.utc(2024, 1, 1, 18).toIso8601String(),
            'isAvailable': true,
          },
        ],
    },
    'blockedDates': const <String>[],
    'bufferMinutes': 0,
  },
};

/// P1 — every public door stays closed to a salon waiting for MyWeli's
/// validation, or refused by it (B0.18 — docs/design/salon-go-live-approval.md
/// §2.1, §8.1).
///
/// R1's whole safety argument is that `pending` and `refused` are `draft`
/// and the validation lives BESIDE the status, so no door needed a change.
/// This pins it door by door: search, the sitemap, the salon page by slug
/// and by id, availability, favourites, and the consumer's booking and
/// reschedule. Each door is checked against a validated, live salon too —
/// an absence that also hid the live salon would prove nothing.
///
/// The fixtures are reached the real way (a request; a request then a
/// refusal; a request then a validation). The red, watched once: the
/// pending fixture set to `active` — every door opens.
///
/// Booking and reschedule are driven through their services, where the
/// refusal lives (`clientBookingRefusal`); the routes' mapping of
/// `provider_not_published` to 409 is pinned by
/// `test/appointments/salon_state_refusal_test.dart`.
void main() {
  late ValidationWorld w;
  late ({String id, String ownerId}) pending;
  late ({String id, String ownerId}) refused;
  late ({String id, String ownerId}) live;
  late InMemoryAppointmentRepository appointments;
  late SlotService slots;
  late FavoritesService favorites;
  final reviews = InMemoryReviewsRepository();

  setUp(() async {
    w = ValidationWorld();
    appointments = InMemoryAppointmentRepository();
    slots = SlotService(w.providers, appointments);
    favorites = FavoritesService(InMemoryFavoritesRepository(), w.providers);

    pending = await w.salon(name: 'Salon En Attente');
    await w.providers.updateProfile(pending.id, _bookable);
    expect((await w.provisioning.publish(pending.id)).accepted, isTrue);

    refused = await w.salon(name: 'Salon Refuse');
    await w.providers.updateProfile(refused.id, _bookable);
    expect((await w.provisioning.publish(refused.id)).accepted, isTrue);
    final r = await w.service.refuse(
      refused.id,
      code: 'photos',
      note: null,
      adminId: 'admin_1',
    );
    expect(r.ok, isTrue, reason: '${r.error}');

    live = await w.salon(name: 'Salon Valide');
    await w.providers.updateProfile(live.id, _bookable);
    await w.validateLive(live.id);

    expect((await w.validations.get(pending.id))!.state, 'pending');
    expect((await w.validations.get(refused.id))!.state, 'refused');
  });

  /// The two salons the doors must keep closed.
  List<String> hidden() => [pending.id, refused.id];

  RequestContext ctx(Request request) {
    final c = _MockRequestContext();
    when(() => c.request).thenReturn(request);
    when(() => c.read<ProvidersRepository>()).thenReturn(w.providers);
    when(() => c.read<ReviewsRepository>()).thenReturn(reviews);
    when(() => c.read<SlotService>()).thenReturn(slots);
    when(() => c.read<FavoritesService>()).thenReturn(favorites);
    when(() => c.read<TokenService>()).thenReturn(w.tokens);
    return c;
  }

  Request get(String path, {String? bearer}) => Request(
    'GET',
    Uri.parse('http://localhost$path'),
    headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
  );

  Future<String> slugOf(String id) async =>
      (await w.providers.byId(id))!['slug'] as String;

  String consumer() =>
      w.tokens.issueAccessToken(subject: 'user_p1', role: 'user').token;

  test('GET /providers (search, discovery): absent', () async {
    final res = await providers_route.onRequest(
      ctx(get('/providers?pageSize=50')),
    );
    expect(res.statusCode, HttpStatus.ok);
    final ids = [
      for (final p in (await bodyOf(res))['items'] as List) (p as Map)['id'],
    ];
    expect(ids, contains(live.id));
    for (final id in hidden()) {
      expect(ids, isNot(contains(id)), reason: id);
    }
  });

  test('GET /sitemap/providers: absent', () async {
    final res = await sitemap_route.onRequest(ctx(get('/sitemap/providers')));
    expect(res.statusCode, HttpStatus.ok);
    final slugs = [
      for (final p in (await bodyOf(res))['items'] as List) (p as Map)['slug'],
    ];
    expect(slugs, contains(await slugOf(live.id)));
    for (final id in hidden()) {
      expect(slugs, isNot(contains(await slugOf(id))), reason: id);
    }
  });

  test('GET /providers/by-slug/{slug}: 404', () async {
    Future<int> status(String id) async {
      final slug = await slugOf(id);
      return (await by_slug_route.onRequest(
        ctx(get('/providers/by-slug/$slug')),
        slug,
      )).statusCode;
    }

    expect(await status(live.id), HttpStatus.ok);
    for (final id in hidden()) {
      expect(await status(id), HttpStatus.notFound, reason: id);
    }
  });

  test('GET /providers/{id}: 404', () async {
    Future<int> status(String id) async => (await provider_route.onRequest(
      ctx(get('/providers/$id')),
      id,
    )).statusCode;

    expect(await status(live.id), HttpStatus.ok);
    for (final id in hidden()) {
      expect(await status(id), HttpStatus.notFound, reason: id);
    }
  });

  test('GET /availability: 404 provider_not_found', () async {
    Future<Response> slotsOf(String id) => availability_route.onRequest(
      ctx(get('/availability?providerId=$id&date=2026-11-16')),
    );

    expect((await slotsOf(live.id)).statusCode, HttpStatus.ok);
    for (final id in hidden()) {
      final res = await slotsOf(id);
      expect(res.statusCode, HttpStatus.notFound, reason: id);
      expect(await bodyOf(res), {'error': 'provider_not_found'}, reason: id);
    }
  });

  test('favourites: adding one → 404; the list never holds it', () async {
    final user = consumer();
    Future<int> add(String id) async => (await favorite_route.onRequest(
      ctx(
        Request(
          'POST',
          Uri.parse('http://localhost/me/favorites/$id'),
          headers: {'Authorization': 'Bearer $user'},
        ),
      ),
      id,
    )).statusCode;

    expect(await add(live.id), HttpStatus.noContent);
    for (final id in hidden()) {
      expect(await add(id), HttpStatus.notFound, reason: id);
    }
    final list = await favorites_route.onRequest(
      ctx(get('/me/favorites', bearer: user)),
    );
    expect(list.statusCode, HttpStatus.ok);
    expect((await bodyOf(list))['providerIds'], [live.id]);
  });

  test('consumer booking: refused, provider_not_published', () async {
    final booking = BookingService(w.providers, appointments, slots);
    final at = w.now.add(const Duration(days: 4));
    Future<String?> book(String id) async => (await booking.book(
      userId: 'user_p1',
      providerId: id,
      serviceIds: const ['s1'],
      appointmentDateTime: at,
    )).error;

    expect(
      await book(live.id),
      isNot(anyOf('provider_not_published', 'provider_suspended')),
    );
    for (final id in hidden()) {
      expect(await book(id), 'provider_not_published', reason: id);
    }
  });

  test('consumer reschedule: refused, provider_not_published', () async {
    final lifecycle = AppointmentLifecycleService(
      appointments,
      slots,
      w.providers,
    );
    final when = w.now.add(const Duration(days: 3));
    // A booking the client already holds at each salon — the move is what
    // the door must refuse.
    for (final id in [live.id, ...hidden()]) {
      await appointments.create({
        'id': 'appt_$id',
        'userId': 'user_p1',
        'providerId': id,
        'serviceIds': const ['s1'],
        'appointmentDate': when.toIso8601String(),
        'durationMinutes': 30,
        'status': 'confirmed',
        'totalPrice': 5000,
        'depositAmount': 0,
        'balanceDue': 5000,
        'createdAt': w.now.toIso8601String(),
      });
    }
    Future<String?> move(String id) async => (await lifecycle.reschedule(
      'appt_$id',
      'user_p1',
      when.add(const Duration(days: 1)),
    )).error;

    expect(
      await move(live.id),
      isNot(anyOf('provider_not_published', 'provider_suspended')),
    );
    for (final id in hidden()) {
      expect(await move(id), 'provider_not_published', reason: id);
    }
  });
}
