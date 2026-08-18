import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/deposit_service.dart';
import 'package:myweli_backend/src/messaging/salon_notifier.dart';
import 'package:myweli_backend/src/notifications/notification_prefs_repository.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/push/device_token_repository.dart';
import 'package:myweli_backend/src/push/push_provider.dart';
import 'package:myweli_backend/src/push/push_service.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:myweli_backend/src/upload_verification_service.dart';
import 'package:test/test.dart';

import '../routes/appointments/index.dart' as appointments_route;

/// **The deposit proof, claimed.**
///
/// `POST /appointments` accepted `depositScreenshotUrl` as an opaque string and
/// wrote it to the column that `DepositService.screenshotUrl` later presigns —
/// for the consumer, the salon AND admins — while that endpoint authorizes on
/// the *appointment* and never on the key. So owning a booking was enough to
/// have the server presign a key you do not own.
///
/// The certain damage was the honest path: the app attaches the key it was just
/// signed, which is a PENDING one, nothing promoted it, and production expires
/// that prefix daily — the payment proof for a real dispute disappeared while
/// the row went on claiming one was attached.
///
/// Design: docs/design/backend-upload-claim-hardening.md §6.1.
void main() {
  const uid = 'user_A';
  const other = 'user_B';
  final tokens = TokenService(secret: 'test-secret');

  late InMemoryProvidersRepository providers;
  late InMemoryAppointmentRepository appts;
  late FakeStorageService store;
  late BookingService booking;

  /// A future Mon–Sat 09:00 UTC — an open slot in the seed schedule.
  DateTime slot() {
    final now = DateTime.now().toUtc();
    var d = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 7));
    while (d.weekday == DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return DateTime.utc(d.year, d.month, d.day, 9);
  }

  void build({FakeStorageService? storage}) {
    providers = InMemoryProvidersRepository();
    appts = InMemoryAppointmentRepository();
    store = storage ?? FakeStorageService(defaultSize: 10);
    booking = BookingService(
      providers,
      appts,
      SlotService(providers, appts),
      verifier: UploadVerificationService(storage: store),
    );
  }

  setUp(build);

  Future<BookingResult> book(String? key, {String as = uid}) => booking.book(
    userId: as,
    providerId: 'provider1',
    serviceIds: const ['service1'],
    appointmentDateTime: slot(),
    depositScreenshotUrl: key,
  );

  group('claiming the proof at booking time', () {
    test('a pending key is promoted, and the PROMOTED key is stored', () async {
      final r = await book('pending/deposit/$uid/x.jpg');
      expect(r.ok, isTrue, reason: 'error was ${r.error}');
      expect(r.appointment!['depositScreenshotUrl'], 'deposit/$uid/x.jpg');
      expect(store.copied, [
        'pending/deposit/$uid/x.jpg -> deposit/$uid/x.jpg',
      ]);
      expect(
        store.deleted,
        ['pending/deposit/$uid/x.jpg'],
        reason: 'the object must LEAVE pending/, or the daily expiry gets it',
      );
      // And it is what was persisted, not just what was echoed back.
      final stored = await appts.byId(r.appointment!['id'] as String);
      expect(stored!['depositScreenshotUrl'], 'deposit/$uid/x.jpg');
    });

    test('a booking with no proof is untouched', () async {
      final r = await book(null);
      expect(r.ok, isTrue);
      expect(r.appointment!['depositScreenshotUrl'], isNull);
      expect(store.copied, isEmpty);
      expect(store.deleted, isEmpty);
    });
  });

  group('the refusals — and NOTHING may be created by one', () {
    /// Every refusal below asserts the repository is empty afterwards. A test
    /// that only checks the returned error would pass against a version that
    /// refuses the proof and books the appointment anyway.
    Future<void> refuses(
      String? key,
      String expected, {
      String as = uid,
    }) async {
      final r = await book(key, as: as);
      expect(r.ok, isFalse, reason: 'expected $expected for $key');
      expect(r.error, expected);
      expect(r.appointment, isNull);
      expect(
        await appts.listForUser(as),
        isEmpty,
        reason: 'a refused proof must not leave a booking behind',
      );
    }

    test("another user's pending key is refused", () async {
      await refuses('pending/deposit/$other/x.jpg', 'invalid_input');
      expect(store.copied, isEmpty);
    });

    test('an already-promoted key is refused', () async {
      // There is no prior row at create time, so `alreadyStored` is empty by
      // construction and the CLAIM form is correct: nothing but a freshly
      // signed, still-pending key may be attached here.
      await refuses('deposit/$uid/x.jpg', 'invalid_input');
    });

    test('a key outside the deposit purpose is refused', () async {
      await refuses('pending/kyc/$uid/passport.pdf', 'invalid_input');
      await refuses('pending/gallery/provider1/a.jpg', 'invalid_input');
    });

    test('a traversal segment does not defeat the prefix check', () async {
      // `startsWith('pending/deposit/user_A/')` is satisfied by this string,
      // which is exactly why the prefix check cannot be the only control:
      // `promotedKey` refuses any `.`/`..`/empty segment.
      await refuses('pending/deposit/$uid/../$other/x.jpg', 'invalid_input');
      await refuses('pending/deposit/$uid/./x.jpg', 'invalid_input');
      await refuses('pending/deposit/$uid//x.jpg', 'invalid_input');
      expect(
        store.copied,
        isEmpty,
        reason: 'nothing may be copied on a refused key',
      );
    });

    test('an oversized proof is refused AND deleted (T61)', () async {
      build(
        storage: FakeStorageService(
          sizes: {'pending/deposit/$uid/big.jpg': 6 * 1024 * 1024},
        ),
      );
      await refuses('pending/deposit/$uid/big.jpg', 'upload_too_large');
      expect(store.deleted, ['pending/deposit/$uid/big.jpg']);
      expect(store.copied, isEmpty);
    });

    test('a claimed-but-absent object is refused', () async {
      build(
        storage: FakeStorageService(
          defaultSize: 10,
          missing: {'pending/deposit/$uid/ghost.jpg'},
        ),
      );
      await refuses('pending/deposit/$uid/ghost.jpg', 'upload_not_found');
    });

    test('unreachable storage FAILS CLOSED', () async {
      build(storage: _ThrowingStorage());
      await refuses('pending/deposit/$uid/x.jpg', 'storage_unavailable');
    });
  });

  group('the read path refuses a key the booking does not own', () {
    late DepositService deposits;
    late String salonAccountId;

    setUp(() async {
      build();
      final providerAuth = InMemoryProviderAuthRepository(
        tokens: tokens,
        echoDevCode: true,
      );
      final reg = await providerAuth.register(
        email: 'dep@test.pro',
        authProvider: 'google',
        googleSub: 'dep-sub',
        phoneNumber: '+2250500000031',
        businessName: 'Salon',
        businessType: 'salon',
        providerId: 'provider1',
      );
      salonAccountId = reg.provider!.id;
      deposits = DepositService(
        appts,
        MembershipService(InMemoryMembershipRepository(), providerAuth),
        store,
      );
    });

    Future<void> seed(String? screenshot) async {
      await appts.create({
        'id': 'a1',
        'userId': uid,
        'providerId': 'provider1',
        'serviceIds': const ['service1'],
        'artistId': null,
        'appointmentDate': DateTime.utc(2030, 6, 10, 9).toIso8601String(),
        'durationMinutes': 60,
        'status': 'pending',
        'totalPrice': 15000,
        'depositAmount': 4500,
        'balanceDue': 10500,
        'depositScreenshotUrl': screenshot,
        'createdAt': DateTime.utc(2030).toIso8601String(),
      });
    }

    test('its own proof presigns for all three audiences', () async {
      await seed('deposit/$uid/x.jpg');
      expect(
        (await deposits.screenshotUrl('a1', sub: uid, role: 'user')).ok,
        isTrue,
      );
      expect(
        (await deposits.screenshotUrl(
          'a1',
          sub: salonAccountId,
          role: 'provider',
        )).ok,
        isTrue,
      );
      expect(
        (await deposits.screenshotUrl('a1', sub: 'admin1', role: 'admin')).ok,
        isTrue,
      );
    });

    test('a FOREIGN key on your own booking presigns for nobody', () async {
      // The defence-in-depth half. Every authorization check above answers
      // "may you see this booking's proof"; none of them answers "is this the
      // booking's own proof". If any write path ever regresses, this is what
      // stops the read from serving it — to the owner, the salon or an admin.
      await seed('deposit/$other/x.jpg');
      for (final who in [
        (sub: uid, role: 'user'),
        (sub: salonAccountId, role: 'provider'),
        (sub: 'admin1', role: 'admin'),
      ]) {
        final r = await deposits.screenshotUrl(
          'a1',
          sub: who.sub,
          role: who.role,
        );
        expect(r.ok, isFalse, reason: '${who.role} must not get a URL');
        expect(r.error, 'not_found');
      }
    });

    test('a still-pending key presigns for nobody either', () async {
      // What every booking-time attachment used to store. It is also the shape
      // `DELETE /me` does not erase, which is why nothing may write it again.
      await seed('pending/deposit/$uid/x.jpg');
      expect(
        (await deposits.screenshotUrl('a1', sub: uid, role: 'user')).error,
        'not_found',
      );
    });
  });

  group('POST /appointments — a wrong-typed body is a 400, not a 500', () {
    Future<Response> post(Map<String, Object?> body) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request(
          'POST',
          Uri.parse('http://localhost/appointments'),
          headers: {
            'Authorization':
                'Bearer ${tokens.issueAccessToken(subject: uid, role: 'user').token}',
          },
          body: jsonEncode(body),
        ),
      );
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<BookingService>()).thenReturn(booking);
      // Only the SUCCESS arm reaches it — a 400 returns before the notify.
      when(() => c.read<SalonNotifier>()).thenReturn(
        SalonNotifier(
          InMemoryMembershipRepository(),
          PushService(LogPushProvider(), InMemoryDeviceTokenRepository()),
          InMemoryNotificationsRepository(),
          InMemoryNotificationPrefsRepository(),
          providers,
        ),
      );
      return appointments_route.onRequest(c);
    }

    test('every string field checks its shape before it is cast', () async {
      // These casts sit OUTSIDE the try that wraps `request.json()`, so a
      // wrong-typed value threw a TypeError into the observability middleware
      // and came back as `internal_error` — plus a Sentry event per request.
      for (final field in const [
        'providerId',
        'appointmentDateTime',
        'artistId',
        'notes',
        'depositScreenshotUrl',
      ]) {
        final res = await post({
          'providerId': 'provider1',
          'serviceIds': const ['service1'],
          'appointmentDateTime': slot().toIso8601String(),
          field: 5,
        });
        expect(
          res.statusCode,
          HttpStatus.badRequest,
          reason: '$field: 5 must be a bad request, not a server error',
        );
        expect(
          jsonDecode(await res.body())['error'],
          'invalid_input',
          reason: 'and it must use the standard envelope',
        );
      }
    });

    test('serviceIds must be a list', () async {
      final res = await post({
        'providerId': 'provider1',
        'serviceIds': 'service1',
        'appointmentDateTime': slot().toIso8601String(),
      });
      expect(res.statusCode, HttpStatus.badRequest);
      expect(jsonDecode(await res.body())['error'], 'invalid_input');
    });

    test('a null optional field is still allowed through', () async {
      // The shape check must not turn "absent" into "invalid" — the app omits
      // `notes` and `depositScreenshotUrl` on most bookings.
      final res = await post({
        'providerId': 'provider1',
        'serviceIds': const ['service1'],
        'appointmentDateTime': slot().toIso8601String(),
        'notes': null,
        'depositScreenshotUrl': null,
      });
      expect(res.statusCode, HttpStatus.created);
    });
  });
}

class _MockRequestContext extends Mock implements RequestContext {}

/// Storage whose every call throws — the fail-closed fixture.
class _ThrowingStorage extends FakeStorageService {
  @override
  Future<int?> objectSize({
    required String key,
    required StorageBucket bucket,
  }) async => throw StateError('unreachable');
}
