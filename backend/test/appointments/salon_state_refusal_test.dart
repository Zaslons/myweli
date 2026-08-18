import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/clients/clients_repository.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/clients/provider_audit_log.dart';
import 'package:myweli_backend/src/messaging/salon_notifier.dart';
import 'package:myweli_backend/src/notifications/notification_prefs_repository.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/push/device_token_repository.dart';
import 'package:myweli_backend/src/push/push_provider.dart';
import 'package:myweli_backend/src/push/push_service.dart';
import 'package:test/test.dart';

import '../../routes/appointments/index.dart' as book_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockAuth extends Mock implements AuthRepository {}

/// A salon that has not published yet is NOT a salon that was stopped
/// (SYSTEM.md §21 row 82, docs/design/salon-state-and-refusals.md).
///
/// **One code carried two statuses carrying four meanings.** `book` and
/// `bookManual` both refused `status == 'suspended' || status == 'draft'` with
/// the single code `provider_suspended`, and no surface had a sentence for it —
/// so every one of them fell through to « Une erreur est survenue. ». The state
/// the code is named for requires a deliberate admin act; the state it is
/// silent about is the one **every** salon starts in.
///
/// Two things are settled here.
///
/// **A draft salon owns its calendar.** `bookManual` refuses `suspended` only.
/// `docs/BACKEND.md` T54 already promises that a billing unpublish
/// (`status → draft`) leaves « journal/bookings/export » working — `bookManual`
/// was silently contradicting a guarantee the threat model had already made.
/// The consequence is that row 82's worst case — the pro's first ever manual
/// booking — stops happening rather than getting better copy.
///
/// **The server carries the distinction, because the client cannot.**
/// `mobile/lib/models/provider.dart` has no `status` field at all, so a client
/// asked to tell a draft from a ban has nothing to read. `draft` splits off as
/// `provider_not_published`; `suspended` keeps its code and its meaning, so no
/// existing code changes meaning and the envelope's stability rule holds.
void main() {
  /// A salon with an explicit [status], isolated from the shared seed.
  ///
  /// **Never `InMemoryProvidersRepository()` here.** It defaults to the
  /// top-level MUTABLE `seedProviders`, `setUp` resets nothing, and
  /// `admin_provider_test.dart:53` already suspends `provider1` without
  /// restoring it. A status test that leaned on the seed would be asserting
  /// against whatever ran before it.
  ///
  /// The map is deliberately thin — the refusal fires before the slot engine,
  /// so nothing here needs an `availability`.
  InMemoryProvidersRepository salonWith(String? status) =>
      InMemoryProvidersRepository([
        {
          'id': 'p',
          'name': 'Salon X',
          'rating': 4.0,
          'category': 'salon',
          if (status != null) 'status': status,
          'services': const [
            {
              'id': 's1',
              'name': 'Coupe',
              'price': 5000,
              'durationMinutes': 30,
              'providerId': 'p',
              'active': true,
            },
          ],
          'availability': {
            'providerId': 'p',
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
        },
      ]);

  BookingService serviceFor(InMemoryProvidersRepository providers) {
    final appts = InMemoryAppointmentRepository();
    return BookingService(providers, appts, SlotService(providers, appts));
  }

  /// `bookManual` never reaches the slot engine (`booking_service.dart` says so
  /// in its own docstring — « the salon owns its calendar »), so a fixed
  /// far-future instant is enough. `book`'s status guard also fires before the
  /// engine, which is why the same instant serves both.
  final at = DateTime.utc(2030, 6, 25, 9);

  group('the consumer funnel tells the two states apart', () {
    test('a DRAFT salon refuses with provider_not_published', () async {
      final res = await serviceFor(salonWith('draft')).book(
        userId: 'u1',
        providerId: 'p',
        serviceIds: const ['s1'],
        appointmentDateTime: at,
      );
      expect(
        res.error,
        'provider_not_published',
        reason:
            'a salon that has never published is not a salon that was '
            'stopped, and no client can tell them apart from one code',
      );
    });

    test('a SUSPENDED salon still refuses with provider_suspended', () async {
      // The over-reach guard, and it is what makes the pair two assertions
      // rather than one wearing two hats (§21 row 78): map 'suspended' to the
      // new code as well and THIS goes red while the test above stays green.
      final res = await serviceFor(salonWith('suspended')).book(
        userId: 'u1',
        providerId: 'p',
        serviceIds: const ['s1'],
        appointmentDateTime: at,
      );
      expect(res.error, 'provider_suspended');
    });

    test(
      'an ACTIVE salon — and one with no status at all — is not refused',
      () async {
        // `seedProviders` carries no `status` key, and Postgres' `_withFlags`
        // reads a NULL column as `'active'`. A guard written as
        // `status != 'active'` would refuse every seeded salon in the suite; this
        // is the assertion that catches that spelling.
        for (final status in [null, 'active']) {
          final res = await serviceFor(salonWith(status)).book(
            userId: 'u1',
            providerId: 'p',
            serviceIds: const ['s1'],
            appointmentDateTime: at,
          );
          expect(
            res.error,
            isNot(anyOf('provider_not_published', 'provider_suspended')),
            reason: 'status $status must not be treated as unpublished',
          );
        }
      },
    );
  });

  group('a draft salon owns its calendar', () {
    test('bookManual SUCCEEDS for a draft salon', () async {
      // The decision, and the reason row 82's worst case disappears instead of
      // being re-worded. A salon entering the appointments it already has,
      // before going live, is ordinary onboarding — and T54 already promised
      // the journal keeps working when a salon is unpublished for billing,
      // which puts it in exactly this state.
      final res = await serviceFor(salonWith('draft')).bookManual(
        providerId: 'p',
        serviceIds: const ['s1'],
        appointmentDateTime: at,
        clientName: 'Awa',
      );
      expect(res.ok, isTrue, reason: 'error was ${res.error}');
      expect(res.appointment!['status'], 'confirmed');
    });

    test('bookManual still REFUSES a suspended salon', () async {
      // The other half of the pair — without it, « a draft may book » could be
      // implemented as « anyone may book » and stay green. Revert the guard to
      // refusing drafts and the test above goes red while this one stays green.
      final res = await serviceFor(salonWith('suspended')).bookManual(
        providerId: 'p',
        serviceIds: const ['s1'],
        appointmentDateTime: at,
        clientName: 'Awa',
      );
      expect(res.error, 'provider_suspended');
    });
  });

  group('the route maps the new code to a CONFLICT, not a bad request', () {
    late TokenService tokens;
    late _MockAuth auth;
    late InMemoryProviderAuthRepository providerAuth;
    late String userToken;

    setUp(() {
      tokens = TokenService(secret: 'test-secret');
      auth = _MockAuth();
      when(() => auth.userById(any())).thenAnswer((_) async => null);
      providerAuth = InMemoryProviderAuthRepository(
        tokens: tokens,
        echoDevCode: true,
      );
      userToken = tokens
          .issueAccessToken(subject: 'user_A', role: 'user')
          .token;
    });

    /// Copied from `appointments_test.dart`'s `routes` group — the book route
    /// reads eight things off the context and a missing stub throws rather
    /// than failing an assertion.
    RequestContext ctx(
      Request request,
      BookingService booking,
      InMemoryProvidersRepository providers,
    ) {
      final appts = InMemoryAppointmentRepository();
      final members = InMemoryMembershipRepository();
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<BookingService>()).thenReturn(booking);
      when(() => context.read<AppointmentRepository>()).thenReturn(appts);
      when(
        () => context.read<ProviderAuthRepository>(),
      ).thenReturn(providerAuth);
      when(
        () => context.read<MembershipService>(),
      ).thenReturn(MembershipService(members, providerAuth));
      when(() => context.read<AuthRepository>()).thenReturn(auth);
      when(() => context.read<ProvidersRepository>()).thenReturn(providers);
      when(() => context.read<SalonNotifier>()).thenReturn(
        SalonNotifier(
          members,
          PushService(LogPushProvider(), InMemoryDeviceTokenRepository()),
          InMemoryNotificationsRepository(),
          InMemoryNotificationPrefsRepository(),
          providers,
        ),
      );
      when(() => context.read<ClientsService>()).thenReturn(
        ClientsService(
          providerAuth,
          MembershipService(members, providerAuth),
          auth,
          InMemoryClientsRepository(),
          appts,
          InMemoryProviderAuditLogRepository(),
        ),
      );
      return context;
    }

    test('POST /appointments on a draft salon → 409, not 400', () async {
      // `routes/appointments/index.dart` warns in its own comment that the
      // fallback arm is a 400 and « a new conflict code added without its own
      // case silently ships as a bad request ». Nothing else in this repo can
      // catch that: there is no test anywhere that compares a route's
      // behaviour to the OpenAPI contract.
      final draft = salonWith('draft');
      final res = await book_route.onRequest(
        ctx(
          Request.post(
            Uri.parse('http://localhost/appointments'),
            headers: {'Authorization': 'Bearer $userToken'},
            body: jsonEncode({
              'providerId': 'p',
              'serviceIds': ['s1'],
              'appointmentDateTime': at.toIso8601String(),
            }),
          ),
          serviceFor(draft),
          draft,
        ),
      );
      expect(res.statusCode, HttpStatus.conflict);
      expect(
        (await res.json() as Map<String, dynamic>)['error'],
        'provider_not_published',
      );
    });
  });
}
