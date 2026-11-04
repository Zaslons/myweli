import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/app_notification.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/messaging.dart';
import 'package:myweli/models/notification_preferences.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/messaging_provider.dart';
import 'package:myweli/providers/notification_preferences_provider.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/services/interfaces/appointment_service_interface.dart';
import 'package:myweli/services/interfaces/favorites_service_interface.dart';
import 'package:myweli/services/interfaces/messaging_service_interface.dart';
import 'package:myweli/services/interfaces/notification_service_interface.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';

class _Appointments extends Mock implements AppointmentServiceInterface {}

class _Notifications extends Mock implements NotificationServiceInterface {}

class _Favorites extends Mock implements FavoritesServiceInterface {}

class _Messaging extends Mock implements MessagingServiceInterface {}

/// docs/design/consumer-account-scope.md §2.1 / §2.3 — each store forgets the
/// account, and an answer to a request sent under it writes nothing after.
void main() {
  late _Appointments appointments;
  late _Notifications notifications;
  late _Favorites favorites;
  late _Messaging messaging;

  setUpAll(() {
    appointments = _Appointments();
    notifications = _Notifications();
    favorites = _Favorites();
    messaging = _Messaging();
    serviceLocator
      ..appointmentService = appointments
      ..notificationService = notifications
      ..favoritesService = favorites
      ..messagingService = messaging
      ..providerService = MockProviderService();
    registerFallbackValue(DateTime(2026));
    registerFallbackValue(<String>[]);
  });

  setUp(() {
    reset(appointments);
    reset(notifications);
    reset(favorites);
    reset(messaging);
  });

  /// How many times [store] notified — "writes nothing" includes "says
  /// nothing": a stale answer must not rebuild the next account's screens.
  int Function() countNotifications(Listenable store) {
    var count = 0;
    store.addListener(() => count++);
    return () => count;
  }

  group('AppointmentProvider', () {
    Appointment booking(String id) => Appointment(
      id: id,
      userId: 'u-$id',
      providerId: const SalonId('p1'),
      serviceIds: const ['s1'],
      appointmentDate: DateTime(2026, 11, 2, 10),
      status: AppointmentStatus.confirmed,
      totalPrice: 20000,
      depositAmount: 6000,
      balanceDue: 14000,
      createdAt: DateTime(2026, 10),
    );

    void listAnswers(List<Future<ApiResponse<List<Appointment>>>> answers) {
      var call = 0;
      when(
        () => appointments.getUserAppointments(status: any(named: 'status')),
      ).thenAnswer((_) => answers[call++]);
    }

    Future<bool> book(AppointmentProvider p) => p.bookAppointment(
      providerId: const SalonId('p1'),
      serviceIds: const ['s1'],
      appointmentDateTime: DateTime(2026, 11, 2, 10),
    );

    void stubBooking(Future<ApiResponse<Appointment>> Function() answer) {
      when(
        () => appointments.bookAppointment(
          providerId: any(named: 'providerId'),
          serviceIds: any(named: 'serviceIds'),
          appointmentDateTime: any(named: 'appointmentDateTime'),
          artistId: any(named: 'artistId'),
          notes: any(named: 'notes'),
          depositAmount: any(named: 'depositAmount'),
          depositScreenshotUrl: any(named: 'depositScreenshotUrl'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((_) => answer());
    }

    test('the reset forgets the list, the selection, the errors', () async {
      final p = AppointmentProvider();
      listAnswers([
        Future.value(ApiResponse.success([booking('a1')])),
      ]);
      await p.loadAppointments();
      when(
        () => appointments.getAppointmentById(any()),
      ).thenAnswer((_) async => ApiResponse.success(booking('a1')));
      await p.loadAppointmentById('a1');
      stubBooking(
        () async => ApiResponse.error('Créneau pris', code: 'slot_unavailable'),
      );
      await book(p);
      expect(p.appointments, isNotEmpty, reason: 'the scenario');
      expect(p.selectedAppointment, isNotNull, reason: 'the scenario');
      expect(p.errorCode, 'slot_unavailable', reason: 'the scenario');
      final notified = countNotifications(p);

      p.resetForAccountChange();

      expect(p.appointments, isEmpty);
      expect(p.selectedAppointment, isNull);
      expect(p.isLoading, isFalse);
      expect(p.error, isNull);
      expect(p.errorCode, isNull);
      expect(p.listError, isNull);
      expect(notified(), 1);
    });

    test(
      'a list read sent under A writes nothing when it answers after',
      () async {
        final aRead = Completer<ApiResponse<List<Appointment>>>();
        final bRead = Completer<ApiResponse<List<Appointment>>>();
        listAnswers([aRead.future, bRead.future]);
        final p = AppointmentProvider();

        final aLoad = p.loadAppointments();
        p.resetForAccountChange();
        final bLoad = p.loadAppointments();
        aRead.complete(ApiResponse.success([booking('a1')]));
        await aLoad;

        expect(p.appointments, isEmpty, reason: 'A\'s list, under B');
        expect(p.isLoading, isTrue, reason: 'B\'s read is still out');

        bRead.complete(ApiResponse.success([booking('b1')]));
        await bLoad;
        expect(p.appointments.map((a) => a.id), ['b1']);
        expect(p.isLoading, isFalse);
      },
    );

    test(
      '…nor its failure: B\'s list is not called broken by A\'s read',
      () async {
        final aRead = Completer<ApiResponse<List<Appointment>>>();
        listAnswers([aRead.future]);
        final p = AppointmentProvider();

        final aLoad = p.loadAppointments();
        p.resetForAccountChange();
        aRead.complete(ApiResponse.error('Hors ligne', code: 'network'));
        await aLoad;

        expect(p.listError, isNull);
        expect(p.error, isNull);
      },
    );

    test(
      'A\'s booking answered after the reset is not added to B\'s list',
      () async {
        final made = Completer<ApiResponse<Appointment>>();
        stubBooking(() => made.future);
        final p = AppointmentProvider();

        final sending = p.bookAppointment(
          providerId: const SalonId('p1'),
          serviceIds: const ['s1'],
          appointmentDateTime: DateTime(2026, 11, 2, 10),
        );
        p.resetForAccountChange();
        listAnswers([
          Future.value(ApiResponse.success([booking('b1')])),
        ]);
        await p.loadAppointments();
        made.complete(ApiResponse.success(booking('a9')));

        expect(
          await sending,
          isTrue,
          reason: 'the booking IS made — on A\'s account, which is right',
        );
        expect(p.appointments.map((a) => a.id), ['b1']);
        expect(p.errorCode, isNull);
      },
    );

    // A buffered push replayed after B signs in opens A's id under B
    // (consumer-account-scope.md §9): A's answer for that SAME id is not B's.
    test('a detail read of A answering after the reset is not B\'s, even for '
        'the same id', () async {
      final aRead = Completer<ApiResponse<Appointment>>();
      final bRead = Completer<ApiResponse<Appointment>>();
      var call = 0;
      when(
        () => appointments.getAppointmentById(any()),
      ).thenAnswer((_) => [aRead, bRead][call++].future);
      final p = AppointmentProvider();

      final aOpen = p.loadAppointmentById('a1');
      p.resetForAccountChange();
      final bOpen = p.loadAppointmentById('a1');
      aRead.complete(ApiResponse.success(booking('a1')));
      await aOpen;

      expect(p.selectedAppointment, isNull);
      expect(p.isLoading, isTrue, reason: 'B\'s read is still out');

      bRead.complete(
        ApiResponse.error('Rendez-vous introuvable.', code: 'not_found'),
      );
      await bOpen;
      expect(p.selectedAppointment, isNull);
      expect(p.error, 'Rendez-vous introuvable.');
    });

    // The three writes on an existing booking: their answer arrives while B's
    // list is loading, and must leave it loading.
    for (final (name, stub, run)
        in <
          (
            String,
            void Function(Future<ApiResponse<Appointment>>),
            Future<bool> Function(AppointmentProvider),
          )
        >[
          (
            'a cancel',
            (answer) =>
                when(() => appointments.cancelAppointment(any())).thenAnswer(
                  (_) async => (await answer).success
                      ? ApiResponse<void>.success(null)
                      : ApiResponse<void>.error('Refus'),
                ),
            (p) => p.cancelAppointment('a1'),
          ),
          (
            'a reschedule',
            (answer) => when(
              () => appointments.rescheduleAppointment(
                id: any(named: 'id'),
                newDateTime: any(named: 'newDateTime'),
              ),
            ).thenAnswer((_) => answer),
            (p) => p.rescheduleAppointment(
              id: 'a1',
              newDateTime: DateTime(2026, 11, 3, 10),
            ),
          ),
          (
            'a deposit',
            (answer) => when(
              () => appointments.submitDeposit(
                appointmentId: any(named: 'appointmentId'),
                screenshotKey: any(named: 'screenshotKey'),
              ),
            ).thenAnswer((_) => answer),
            (p) => p.submitDeposit(appointmentId: 'a1', screenshotKey: 'k'),
          ),
        ]) {
      test(
        '$name of A answered after the reset leaves B\'s state alone',
        () async {
          final written = Completer<ApiResponse<Appointment>>();
          stub(written.future);
          final bRead = Completer<ApiResponse<List<Appointment>>>();
          listAnswers([bRead.future]);
          final p = AppointmentProvider();

          final writing = run(p);
          p.resetForAccountChange();
          unawaited(p.loadAppointments());
          written.complete(ApiResponse.error('Refus', code: 'invalid_state'));
          await writing;

          expect(p.isLoading, isTrue, reason: 'B\'s read is still out');
          expect(p.error, isNull, reason: 'A\'s refusal, shown to B');
          expect(p.selectedAppointment, isNull);
          bRead.complete(ApiResponse.success(const []));
        },
      );
    }

    test(
      'the next account\'s first submission gets a new Idempotency-Key',
      () async {
        final keys = <String?>[];
        when(
          () => appointments.bookAppointment(
            providerId: any(named: 'providerId'),
            serviceIds: any(named: 'serviceIds'),
            appointmentDateTime: any(named: 'appointmentDateTime'),
            artistId: any(named: 'artistId'),
            notes: any(named: 'notes'),
            depositAmount: any(named: 'depositAmount'),
            depositScreenshotUrl: any(named: 'depositScreenshotUrl'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ),
        ).thenAnswer((call) async {
          keys.add(call.namedArguments[#idempotencyKey] as String?);
          return ApiResponse.error('Pas de connexion.', code: 'network');
        });
        final p = AppointmentProvider();

        await book(p);
        p.resetForAccountChange();
        await book(p);

        expect(keys, hasLength(2));
        expect(
          keys.last,
          isNot(keys.first),
          reason: 'the same form under another account is another submission',
        );
      },
    );

    // A failed list read empties the list (F1), so its error is its own
    // scenario.
    test('the reset forgets a failed list read', () async {
      listAnswers([Future.value(ApiResponse.error('Hors ligne'))]);
      final p = AppointmentProvider();
      await p.loadAppointments();
      expect(p.listError, isNotNull, reason: 'the scenario');

      p.resetForAccountChange();

      expect(p.listError, isNull);
      expect(p.error, isNull);
    });

    test('the reset ends A\'s loading', () async {
      listAnswers([Completer<ApiResponse<List<Appointment>>>().future]);
      final p = AppointmentProvider();
      unawaited(p.loadAppointments());
      expect(p.isLoading, isTrue, reason: 'the scenario');

      p.resetForAccountChange();

      expect(p.isLoading, isFalse);
    });
  });

  group('NotificationsProvider', () {
    AppNotification notification(String id, {bool read = false}) =>
        AppNotification(
          id: id,
          type: AppNotificationType.general,
          title: 'Titre $id',
          body: 'Corps',
          createdAt: DateTime(2026, 10),
          read: read,
        );

    test('the reset forgets the list and the failed read', () async {
      when(
        () => notifications.getNotifications(),
      ).thenAnswer((_) async => ApiResponse.success([notification('a1')]));
      final p = NotificationsProvider();
      await p.load();
      when(
        () => notifications.getNotifications(),
      ).thenAnswer((_) async => ApiResponse.error('Hors ligne'));
      await p.load();
      expect(p.loadFailed, isTrue, reason: 'the scenario');
      when(
        () => notifications.getNotifications(),
      ).thenAnswer((_) async => ApiResponse.success([notification('a1')]));
      await p.load();
      final notified = countNotifications(p);

      p.resetForAccountChange();

      expect(p.notifications, isEmpty);
      expect(p.unreadCount, 0);
      expect(p.loadFailed, isFalse);
      expect(p.error, isNull);
      expect(p.isLoading, isFalse);
      expect(notified(), 1);
    });

    test('a read sent under A writes nothing when it answers after', () async {
      final aRead = Completer<ApiResponse<List<AppNotification>>>();
      final bRead = Completer<ApiResponse<List<AppNotification>>>();
      var call = 0;
      when(
        () => notifications.getNotifications(),
      ).thenAnswer((_) => [aRead, bRead][call++].future);
      final p = NotificationsProvider();

      final aLoad = p.load();
      p.resetForAccountChange();
      final bLoad = p.load();
      aRead.complete(ApiResponse.success([notification('a1')]));
      await aLoad;

      expect(p.notifications, isEmpty);
      expect(p.isLoading, isTrue, reason: 'B\'s read is still out');

      bRead.complete(ApiResponse.success([notification('b1')]));
      await bLoad;
      expect(p.notifications.map((n) => n.id), ['b1']);
      expect(p.isLoading, isFalse);
    });

    test('a « lu » of A answering after the reset changes nothing', () async {
      when(
        () => notifications.getNotifications(),
      ).thenAnswer((_) async => ApiResponse.success([notification('a1')]));
      final written = Completer<ApiResponse<bool>>();
      when(
        () => notifications.markRead(any()),
      ).thenAnswer((_) => written.future);
      final p = NotificationsProvider();
      await p.load();

      final marking = p.markRead('a1');
      p.resetForAccountChange();
      final notified = countNotifications(p);
      written.complete(ApiResponse.error('Refus', code: 'forbidden'));
      await marking;

      expect(p.notifications, isEmpty);
      expect(notified(), 0, reason: 'A\'s write rebuilt B\'s screens');
    });

    test('the reset forgets a failed read', () async {
      when(
        () => notifications.getNotifications(),
      ).thenAnswer((_) async => ApiResponse.error('Hors ligne'));
      final p = NotificationsProvider();
      await p.load();
      expect(p.loadFailed, isTrue, reason: 'the scenario');

      p.resetForAccountChange();

      expect(p.loadFailed, isFalse);
      expect(p.error, isNull);
    });

    test('the reset ends A\'s loading', () async {
      when(() => notifications.getNotifications()).thenAnswer(
        (_) => Completer<ApiResponse<List<AppNotification>>>().future,
      );
      final p = NotificationsProvider();
      unawaited(p.load());
      expect(p.isLoading, isTrue, reason: 'the scenario');

      p.resetForAccountChange();

      expect(p.isLoading, isFalse);
    });

    // A's read that never counts itself down would leave B's feed believing
    // a reload is always out: every « lu » B confirms would then be forced
    // read over the server's list for the rest of the session.
    test(
      'A\'s read still out does not leave B\'s count of reads wrong',
      () async {
        final aRead = Completer<ApiResponse<List<AppNotification>>>();
        final answers = <Future<ApiResponse<List<AppNotification>>>>[
          aRead.future,
          Future.value(ApiResponse.success([notification('b1')])),
          // The server's list, later: b1 unread again (marked unread on
          // another device — whatever; once no reload is out, the server's
          // list rules).
          Future.value(ApiResponse.success([notification('b1')])),
        ];
        var call = 0;
        when(
          () => notifications.getNotifications(),
        ).thenAnswer((_) => answers[call++]);
        when(
          () => notifications.markRead(any()),
        ).thenAnswer((_) async => ApiResponse.success(true));
        final p = NotificationsProvider();

        unawaited(p.load());
        p.resetForAccountChange();
        await p.load();
        await p.markRead('b1');
        await p.load();

        expect(p.notifications.single.read, isFalse);
      },
    );
  });

  group('NotificationPreferencesProvider', () {
    const ofA = NotificationPreferences(marketing: false);

    test('the reset forgets A\'s switches', () async {
      when(
        () => notifications.getPreferences(),
      ).thenAnswer((_) async => ApiResponse.success(ofA));
      final p = NotificationPreferencesProvider();
      await p.load();
      expect(p.loadedPrefs, ofA, reason: 'the scenario');
      final notified = countNotifications(p);

      p.resetForAccountChange();

      expect(p.loadedPrefs, isNull);
      expect(p.prefs, const NotificationPreferences());
      expect(p.loadFailed, isFalse);
      expect(p.saving, isFalse);
      expect(p.error, isNull);
      expect(notified(), 1);
    });

    test('a read sent under A writes nothing when it answers after', () async {
      final aRead = Completer<ApiResponse<NotificationPreferences>>();
      when(
        () => notifications.getPreferences(),
      ).thenAnswer((_) => aRead.future);
      final p = NotificationPreferencesProvider();

      final aLoad = p.load();
      p.resetForAccountChange();
      aRead.complete(ApiResponse.success(ofA));
      await aLoad;

      expect(p.loadedPrefs, isNull);
    });

    // The revert of a refused save restores what A had — on B's screen.
    test(
      'a save of A refused after the reset does not restore A\'s switch',
      () async {
        when(
          () => notifications.getPreferences(),
        ).thenAnswer((_) async => ApiResponse.success(ofA));
        final saved = Completer<ApiResponse<NotificationPreferences>>();
        when(
          () => notifications.updatePreferences(
            reminders: any(named: 'reminders'),
            marketing: any(named: 'marketing'),
            push: any(named: 'push'),
          ),
        ).thenAnswer((_) => saved.future);
        final p = NotificationPreferencesProvider();
        await p.load();

        final saving = p.setMarketing(true);
        p.resetForAccountChange();
        saved.complete(ApiResponse.error('Refus'));
        await saving;

        expect(p.prefs, const NotificationPreferences());
        expect(p.error, isNull);
        expect(p.loadedPrefs, isNull);
        expect(p.saving, isFalse, reason: 'B\'s switches would stay locked');
      },
    );

    test('the reset forgets a failed read, ends a load and a save', () async {
      when(
        () => notifications.getPreferences(),
      ).thenAnswer((_) async => ApiResponse.error('Hors ligne'));
      final p = NotificationPreferencesProvider();
      await p.load();
      expect(p.loadFailed, isTrue, reason: 'the scenario');
      p.resetForAccountChange();
      expect(p.loadFailed, isFalse);
      expect(p.error, isNull);

      when(() => notifications.getPreferences()).thenAnswer(
        (_) => Completer<ApiResponse<NotificationPreferences>>().future,
      );
      unawaited(p.load());
      expect(p.isLoading, isTrue, reason: 'the scenario');
      p.resetForAccountChange();
      expect(p.isLoading, isFalse);

      when(
        () => notifications.updatePreferences(
          reminders: any(named: 'reminders'),
          marketing: any(named: 'marketing'),
          push: any(named: 'push'),
        ),
      ).thenAnswer(
        (_) => Completer<ApiResponse<NotificationPreferences>>().future,
      );
      unawaited(p.setPush(false));
      expect(p.saving, isTrue, reason: 'the scenario');
      p.resetForAccountChange();
      expect(p.saving, isFalse);
    });
  });

  group('FavoritesProvider', () {
    final salon = MockData.providers.first;

    test('the reset forgets the favourites', () async {
      when(
        () => favorites.getFavoriteProviders(any()),
      ).thenAnswer((_) async => ApiResponse.success([salon]));
      final p = FavoritesProvider();
      await p.loadFavorites('a');
      expect(p.isFavorite(salon.id), isTrue, reason: 'the scenario');
      final notified = countNotifications(p);

      p.resetForAccountChange();

      expect(p.favoriteProviderIds, isEmpty);
      expect(p.favoriteProviders, isEmpty);
      expect(p.isLoading, isFalse);
      expect(p.error, isNull);
      expect(notified(), 1);
    });

    test('a read sent under A writes nothing when it answers after', () async {
      final aRead = Completer<ApiResponse<List<Provider>>>();
      when(
        () => favorites.getFavoriteProviders(any()),
      ).thenAnswer((_) => aRead.future);
      final p = FavoritesProvider();

      final aLoad = p.loadFavorites('a');
      p.resetForAccountChange();
      aRead.complete(ApiResponse.success([salon]));
      await aLoad;

      expect(p.isFavorite(salon.id), isFalse);
      expect(p.favoriteProviders, isEmpty);
    });

    test('a heart of A answered after the reset is not B\'s', () async {
      when(
        () => favorites.getFavoriteProviders(any()),
      ).thenAnswer((_) async => ApiResponse.success(const []));
      final added = Completer<ApiResponse<bool>>();
      when(
        () => favorites.addFavorite(any(), any()),
      ).thenAnswer((_) => added.future);
      final p = FavoritesProvider();
      await p.loadFavorites('a');

      final toggling = p.toggleFavorite('a', salon.id);
      await pumpEventQueue();
      p.resetForAccountChange();
      added.complete(ApiResponse.success(true));

      expect(await toggling, isTrue, reason: 'it IS A\'s favourite now');
      expect(p.isFavorite(salon.id), isFalse);
    });

    test('the reset forgets a failed read and ends a load', () async {
      when(
        () => favorites.getFavoriteProviders(any()),
      ).thenAnswer((_) async => ApiResponse.error('Hors ligne'));
      final p = FavoritesProvider();
      await p.loadFavorites('a');
      expect(p.error, isNotNull, reason: 'the scenario');
      p.resetForAccountChange();
      expect(p.error, isNull);

      when(
        () => favorites.getFavoriteProviders(any()),
      ).thenAnswer((_) => Completer<ApiResponse<List<Provider>>>().future);
      unawaited(p.loadFavorites('a'));
      expect(p.isLoading, isTrue, reason: 'the scenario');
      p.resetForAccountChange();
      expect(p.isLoading, isFalse);
    });

    // A heart tapped before the favourites were read reads them first: an
    // account change during THAT read sends nothing for A afterwards.
    test(
      'a heart of A waiting on its read sends nothing after the reset',
      () async {
        final aRead = Completer<ApiResponse<List<Provider>>>();
        when(
          () => favorites.getFavoriteProviders(any()),
        ).thenAnswer((_) => aRead.future);
        when(
          () => favorites.addFavorite(any(), any()),
        ).thenAnswer((_) async => ApiResponse.success(true));
        final p = FavoritesProvider();

        final toggling = p.toggleFavorite('a', salon.id);
        await pumpEventQueue();
        p.resetForAccountChange();
        aRead.complete(ApiResponse.success(const []));

        expect(await toggling, isFalse);
        verifyNever(() => favorites.addFavorite(any(), any()));
        expect(p.isFavorite(salon.id), isFalse);
      },
    );
  });

  group('MessagingProvider', () {
    OutboundMessage message(String id) => OutboundMessage(
      id: id,
      recipientPhone: '+2250700000001',
      channel: MessageChannel.whatsApp,
      template: MessageTemplate.bookingConfirmed,
      params: const {},
      body: 'Rendez-vous confirmé',
      status: DeliveryStatus.sent,
      createdAt: DateTime(2026, 10),
    );

    test('the reset forgets the outbox', () async {
      when(
        () => messaging.getOutbox(),
      ).thenAnswer((_) async => ApiResponse.success([message('m1')]));
      final p = MessagingProvider();
      await p.refreshOutbox();
      expect(p.outbox, isNotEmpty, reason: 'the scenario');

      p.resetForAccountChange();

      expect(p.outbox, isEmpty);
    });

    test('a read sent under A writes nothing when it answers after', () async {
      final aRead = Completer<ApiResponse<List<OutboundMessage>>>();
      when(() => messaging.getOutbox()).thenAnswer((_) => aRead.future);
      final p = MessagingProvider();

      final reading = p.refreshOutbox();
      p.resetForAccountChange();
      aRead.complete(ApiResponse.success([message('m1')]));
      await reading;

      expect(p.outbox, isEmpty);
    });
  });

  group('ProviderProvider', () {
    // The stars A gave each visit are A's; the salons are everybody's.
    test('the reset forgets the stars A gave, and keeps the salons', () async {
      final p = ProviderProvider();
      await p.loadProviders();
      final salon = p.providers.first;
      final count = salon.reviewCount;
      Review review(String id, int stars) => Review(
        id: id,
        appointmentId: 'visit-a',
        providerId: salon.id,
        userId: 'a',
        userName: 'A',
        rating: stars,
        text: '',
        createdAt: DateTime(2026, 10),
      );
      p.addReviewLocally(review('r1', 5));
      expect(
        p.providers.first.reviewCount,
        count + 1,
        reason: 'the scenario: a first review of that visit',
      );

      p.resetForAccountChange();

      expect(p.providers, isNotEmpty, reason: 'the salons are public');
      // Remembered, this would be the same visit reviewed AGAIN — a
      // replacement, the count unchanged.
      p.addReviewLocally(review('r2', 3));
      expect(p.providers.first.reviewCount, count + 2);
    });
  });
}
