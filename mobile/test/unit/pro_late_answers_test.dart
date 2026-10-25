import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/artist.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/models/before_after_pair.dart';
import 'package:myweli/models/journal_day.dart';
import 'package:myweli/models/kyc_document.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/review_summary.dart';
import 'package:myweli/models/salon_client.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/service.dart';
import 'package:myweli/models/team_invitation.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/providers/pro_artist_provider.dart';
import 'package:myweli/providers/pro_availability_provider.dart';
import 'package:myweli/providers/pro_before_after_provider.dart';
import 'package:myweli/providers/pro_clients_provider.dart';
import 'package:myweli/providers/pro_deposit_settings_provider.dart';
import 'package:myweli/providers/pro_earnings_provider.dart';
import 'package:myweli/providers/pro_gallery_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/providers/pro_kyc_provider.dart';
import 'package:myweli/providers/pro_onboarding_provider.dart';
import 'package:myweli/providers/pro_reviews_provider.dart';
import 'package:myweli/providers/pro_salon_profile_provider.dart';
import 'package:myweli/providers/pro_service_provider.dart';
import 'package:myweli/providers/pro_subscription_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/services/interfaces/image_upload_service_interface.dart';
import 'package:myweli/services/interfaces/pro_artist_service_interface.dart';
import 'package:myweli/services/interfaces/pro_clients_service_interface.dart';
import 'package:myweli/services/interfaces/pro_kyc_service_interface.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/interfaces/pro_team_service_interface.dart';
import 'package:myweli/services/interfaces/subscription_service_interface.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_pro_clients_service.dart';

class _Pro extends Mock implements ProServiceInterface {}

class _Artists extends Mock implements ProArtistServiceInterface {}

class _Team extends Mock implements ProTeamServiceInterface {}

class _Kyc extends Mock implements ProKycServiceInterface {}

class _Subscriptions extends Mock implements SubscriptionServiceInterface {}

class _Clients extends Mock implements ProClientsServiceInterface {}

class _Uploads extends Mock implements ImageUploadServiceInterface {}

/// A store that hears the bookings the journal announces.
class _Ear implements HearsBookingChanges {
  final heard = <String>[];
  @override
  void bookingChanged(BookingChange change) => heard.add(change.appointmentId);
  @override
  void resetForSalonSwitch() {}
}

/// Which way the held call lands in the current group — see [_Land].
bool _throwing = false;

extension _Land<T> on Completer<T> {
  /// Answers [value], or throws, by the group the case runs in.
  void land(T value) =>
      _throwing ? completeError(StateError('offline')) : complete(value);
}

/// What every refused call answers here — a code that triggers nothing else
/// (`ProAccessGuard` acts on `forbidden` only).
ApiResponse<T> refused<T>() =>
    ApiResponse<T>.error('Refus', code: 'invalid_input');

/// docs/design/pro-account-scope.md §2.2 (Q1 = a) — a read or a write sent
/// for the previous salon or account writes nothing when it answers after the
/// reset: not its data, not its error, not its `isLoading` — and so it does
/// not notify. Each case holds ONE await of one method, resets, answers it.
void main() {
  late _Pro pro;
  late _Artists artists;
  late _Team team;
  late _Kyc kyc;
  late _Subscriptions subscriptions;
  late _Clients clients;
  late _Uploads uploads;
  late _Uploads logos;

  setUpAll(() {
    pro = _Pro();
    artists = _Artists();
    team = _Team();
    kyc = _Kyc();
    subscriptions = _Subscriptions();
    clients = _Clients();
    uploads = _Uploads();
    logos = _Uploads();
    serviceLocator
      ..proService = pro
      ..proArtistService = artists
      ..proTeamService = team
      ..proKycService = kyc
      ..subscriptionService = subscriptions
      ..proClientsService = clients
      ..imageUploadService = uploads
      ..logoImageUploadService = logos;
    registerFallbackValue(DateTime(2026));
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<String>[]);
    registerFallbackValue(<BeforeAfterPair>[]);
    registerFallbackValue(<KycDocument>[]);
    registerFallbackValue(TeamRole.staff);
    registerFallbackValue(
      const Availability(providerId: 'p', weeklySchedule: {}, blockedDates: []),
    );
  });

  setUp(() {
    for (final m in <Mock>[
      pro,
      artists,
      team,
      kyc,
      subscriptions,
      clients,
      uploads,
      logos,
    ]) {
      reset(m);
    }
  });

  /// Starts [call], lets it reach its held await, resets [store], then lets
  /// [answer] land — and expects nothing to have been said.
  Future<void> expectIgnored<S extends ChangeNotifier>(
    String what,
    S store,
    void Function(S) resetStore,
    Future<Object?> Function(S) call,
    void Function() answer,
  ) async {
    final pending = call(store);
    await pumpEventQueue();
    resetStore(store);
    var notified = 0;
    store.addListener(() => notified++);
    answer();
    try {
      await pending;
    } catch (_) {
      // A method with no `catch` lets a thrown answer through; what matters
      // is that it wrote nothing on its way out.
    }
    await pumpEventQueue();
    expect(
      notified,
      0,
      reason: '$what: the previous salon\'s answer rebuilt the next screens',
    );
  }

  void salonReset(SalonScoped s) => s.resetForSalonSwitch();

  // Every case twice: the call answers, or it THROWS — the `catch` blocks
  // write an error too, and need the same guard.
  for (final throwing in [false, true]) {
    group(throwing ? 'a thrown answer' : 'an answer', () {
      setUp(() => _throwing = throwing);

      group('ProAppointmentProvider', () {
        test('loadAppointments', () async {
          final held = Completer<ApiResponse<List<Appointment>>>();
          when(
            () => pro.getProviderAppointments(
              any(),
              status: any(named: 'status'),
              startDate: any(named: 'startDate'),
              endDate: any(named: 'endDate'),
            ),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'loadAppointments',
            ProAppointmentProvider(),
            salonReset,
            (s) => s.loadAppointments('p1'),
            () => held.land(refused()),
          );
        });

        for (final (name, stub, run)
            in <
              (
                String,
                void Function(Future<ApiResponse<bool>>),
                Future<bool> Function(ProAppointmentProvider),
              )
            >[
              (
                'acceptAppointment',
                (f) => when(
                  () => pro.acceptAppointment(any()),
                ).thenAnswer((_) => f),
                (s) => s.acceptAppointment('a1'),
              ),
              (
                'rejectAppointment',
                (f) => when(
                  () => pro.rejectAppointment(any(), any()),
                ).thenAnswer((_) => f),
                (s) => s.rejectAppointment('a1', null),
              ),
              (
                'markComplete',
                (f) => when(
                  () => pro.markAppointmentComplete(any()),
                ).thenAnswer((_) => f),
                (s) => s.markComplete('a1'),
              ),
              (
                'markNoShow',
                (f) => when(() => pro.markNoShow(any())).thenAnswer((_) => f),
                (s) => s.markNoShow('a1'),
              ),
              (
                'reschedule',
                (f) => when(
                  () => pro.rescheduleAppointment(any(), any()),
                ).thenAnswer((_) => f),
                (s) => s.reschedule('a1', DateTime(2026, 11, 2, 10)),
              ),
            ]) {
          test(name, () async {
            final held = Completer<ApiResponse<bool>>();
            stub(held.future);
            await expectIgnored(
              name,
              ProAppointmentProvider(),
              salonReset,
              run,
              () => held.land(refused()),
            );
          });
        }

        test('createManualBooking', () async {
          final held = Completer<ApiResponse<Appointment>>();
          when(
            () => pro.createManualBooking(
              providerId: any(named: 'providerId'),
              serviceIds: any(named: 'serviceIds'),
              appointmentDateTime: any(named: 'appointmentDateTime'),
              clientName: any(named: 'clientName'),
              clientPhone: any(named: 'clientPhone'),
              notes: any(named: 'notes'),
              artistId: any(named: 'artistId'),
              sendSmsInvite: any(named: 'sendSmsInvite'),
              idempotencyKey: any(named: 'idempotencyKey'),
            ),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'createManualBooking',
            ProAppointmentProvider(),
            salonReset,
            (s) => s.createManualBooking(
              providerId: 'p1',
              serviceIds: const ['s1'],
              appointmentDateTime: DateTime(2026, 11, 2, 10),
            ),
            () => held.land(refused()),
          );
        });
      });

      group('ProArtistProvider', () {
        test('uploadAvatar', () async {
          final held = Completer<ApiResponse<String>>();
          when(
            () => uploads.uploadImage(
              source: any(named: 'source'),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'uploadAvatar',
            ProArtistProvider(),
            salonReset,
            (s) => s.uploadAvatar('/tmp/a.jpg'),
            () => held.land(refused()),
          );
        });

        test('an upload\'s progress after the reset says nothing', () async {
          void Function(double)? progress;
          final held = Completer<ApiResponse<String>>();
          when(
            () => uploads.uploadImage(
              source: any(named: 'source'),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((call) {
            progress =
                call.namedArguments[#onProgress] as void Function(double)?;
            return held.future;
          });
          await expectIgnored(
            'uploadAvatar progress',
            ProArtistProvider(),
            salonReset,
            (s) => s.uploadAvatar('/tmp/a.jpg'),
            () {
              progress!(0.5);
              held.land(refused());
            },
          );
        });

        test('loadArtists', () async {
          final held = Completer<ApiResponse<List<Artist>>>();
          when(() => artists.getArtists(any())).thenAnswer((_) => held.future);
          await expectIgnored(
            'loadArtists',
            ProArtistProvider(),
            salonReset,
            (s) => s.loadArtists('p1'),
            () => held.land(refused()),
          );
        });

        test('createArtist', () async {
          final held = Completer<ApiResponse<Artist>>();
          when(
            () => artists.createArtist(any(), any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'createArtist',
            ProArtistProvider(),
            salonReset,
            (s) => s.createArtist('p1', const {}),
            () => held.land(refused()),
          );
        });

        test('updateArtist', () async {
          final held = Completer<ApiResponse<Artist>>();
          when(
            () => artists.updateArtist(any(), any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'updateArtist',
            ProArtistProvider(),
            salonReset,
            (s) => s.updateArtist('a1', const {}),
            () => held.land(refused()),
          );
        });

        test('deleteArtist', () async {
          final held = Completer<ApiResponse<bool>>();
          when(
            () => artists.deleteArtist(any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'deleteArtist',
            ProArtistProvider(),
            salonReset,
            (s) => s.deleteArtist('a1'),
            () => held.land(refused()),
          );
        });
      });

      group('ProAvailabilityProvider', () {
        test('loadAvailability', () async {
          final held = Completer<ApiResponse<Availability>>();
          when(
            () => pro.getProviderAvailability(any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'loadAvailability',
            ProAvailabilityProvider(),
            salonReset,
            (s) => s.loadAvailability('p1'),
            () => held.land(refused()),
          );
        });

        test('updateAvailability', () async {
          final held = Completer<ApiResponse<Availability>>();
          when(
            () => pro.updateAvailability(any(), any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'updateAvailability',
            ProAvailabilityProvider(),
            salonReset,
            (s) => s.updateAvailability(
              'p1',
              const Availability(
                providerId: 'p1',
                weeklySchedule: {},
                blockedDates: [],
              ),
            ),
            () => held.land(refused()),
          );
        });
      });

      group('ProBeforeAfterProvider', () {
        test('load', () async {
          final held = Completer<ApiResponse<List<BeforeAfterPair>>>();
          when(() => pro.getBeforeAfters(any())).thenAnswer((_) => held.future);
          await expectIgnored(
            'load',
            ProBeforeAfterProvider(),
            salonReset,
            (s) => s.load('p1'),
            () => held.land(refused()),
          );
        });

        // The first photo of a pair finished after the reset: the list the save
        // would send is built from the NEXT salon's pairs (none) — it would
        // replace the previous salon's whole showcase with one pair.
        for (final point in ['the first photo', 'the second photo']) {
          test(
            'addPair: $point answered after the reset saves nothing',
            () async {
              final held = Completer<ApiResponse<String>>();
              var uploadsMade = 0;
              when(
                () => uploads.uploadImage(
                  source: any(named: 'source'),
                  onProgress: any(named: 'onProgress'),
                ),
              ).thenAnswer((_) {
                uploadsMade++;
                if (point == 'the second photo' && uploadsMade == 1) {
                  return Future.value(
                    ApiResponse.success('https://cdn/before.jpg'),
                  );
                }
                return held.future;
              });
              when(
                () => pro.updateBeforeAfters(any(), any()),
              ).thenAnswer((_) async => ApiResponse.success(const []));
              await expectIgnored(
                'addPair ($point)',
                ProBeforeAfterProvider(),
                salonReset,
                (s) => s.addPair('p1', beforeSource: 'b', afterSource: 'a'),
                () => held.land(ApiResponse.success('https://cdn/x.jpg')),
              );
              verifyNever(() => pro.updateBeforeAfters(any(), any()));
            },
          );
        }

        test('addPair: the save answered after the reset', () async {
          when(
            () => uploads.uploadImage(
              source: any(named: 'source'),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((_) async => ApiResponse.success('https://cdn/x.jpg'));
          final held = Completer<ApiResponse<List<BeforeAfterPair>>>();
          when(
            () => pro.updateBeforeAfters(any(), any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'addPair (the save)',
            ProBeforeAfterProvider(),
            salonReset,
            (s) => s.addPair('p1', beforeSource: 'b', afterSource: 'a'),
            () => held.land(refused()),
          );
        });

        test('an upload\'s progress after the reset says nothing', () async {
          void Function(double)? progress;
          final held = Completer<ApiResponse<String>>();
          when(
            () => uploads.uploadImage(
              source: any(named: 'source'),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((call) {
            progress =
                call.namedArguments[#onProgress] as void Function(double)?;
            return held.future;
          });
          await expectIgnored(
            'addPair progress',
            ProBeforeAfterProvider(),
            salonReset,
            (s) => s.addPair('p1', beforeSource: 'b', afterSource: 'a'),
            () {
              progress!(0.5);
              held.land(refused());
            },
          );
        });

        for (final (name, run)
            in <(String, Future<bool> Function(ProBeforeAfterProvider))>[
              (
                'restorePairAt',
                (s) => s.restorePairAt(
                  'p1',
                  0,
                  const BeforeAfterPair(before: 'b', after: 'a'),
                ),
              ),
              (
                'removePair',
                (s) async {
                  // A pair to remove: the load answers first.
                  when(() => pro.getBeforeAfters(any())).thenAnswer(
                    (_) async => ApiResponse.success(const [
                      BeforeAfterPair(before: 'b', after: 'a'),
                    ]),
                  );
                  await s.load('p1');
                  return s.removePair('p1', 0);
                },
              ),
            ]) {
          test(name, () async {
            final held = Completer<ApiResponse<List<BeforeAfterPair>>>();
            when(
              () => pro.updateBeforeAfters(any(), any()),
            ).thenAnswer((_) => held.future);
            await expectIgnored(
              name,
              ProBeforeAfterProvider(),
              salonReset,
              run,
              () => held.land(refused()),
            );
          });
        }
      });

      group('ProDepositSettingsProvider', () {
        test('load', () async {
          final held = Completer<ApiResponse<DepositPolicy>>();
          when(
            () => pro.getDepositPolicy(any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'load',
            ProDepositSettingsProvider(),
            salonReset,
            (s) => s.load('p1'),
            () => held.land(refused()),
          );
        });

        test('save', () async {
          final held = Completer<ApiResponse<DepositPolicy>>();
          when(
            () => pro.updateDepositPolicy(
              any(),
              depositRequired: any(named: 'depositRequired'),
              depositPercentage: any(named: 'depositPercentage'),
              cancellationWindowHours: any(named: 'cancellationWindowHours'),
              mobileMoneyOperator: any(named: 'mobileMoneyOperator'),
              mobileMoneyNumber: any(named: 'mobileMoneyNumber'),
            ),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'save',
            ProDepositSettingsProvider(),
            salonReset,
            (s) => s.save('p1'),
            () => held.land(refused()),
          );
        });
      });

      group('ProEarningsProvider', () {
        test('loadEarnings', () async {
          final held = Completer<ApiResponse<EarningsData>>();
          when(
            () => pro.getEarnings(
              any(),
              startDate: any(named: 'startDate'),
              endDate: any(named: 'endDate'),
            ),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'loadEarnings',
            ProEarningsProvider(),
            salonReset,
            (s) => s.loadEarnings('p1'),
            () => held.land(refused()),
          );
        });
      });

      group('ProGalleryProvider', () {
        test('load', () async {
          final held = Completer<ApiResponse<List<String>>>();
          when(
            () => pro.getGalleryPhotos(any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'load',
            ProGalleryProvider(),
            salonReset,
            (s) => s.load('p1'),
            () => held.land(refused()),
          );
        });

        // Same shape as addPair: the list saved would be the next salon's
        // (empty) plus one photo — the previous salon's gallery, replaced.
        test(
          'addPhoto: the upload answered after the reset saves nothing',
          () async {
            final held = Completer<ApiResponse<String>>();
            when(
              () => uploads.uploadImage(
                source: any(named: 'source'),
                onProgress: any(named: 'onProgress'),
              ),
            ).thenAnswer((_) => held.future);
            when(
              () => pro.updateGalleryPhotos(any(), any()),
            ).thenAnswer((_) async => ApiResponse.success(const []));
            await expectIgnored(
              'addPhoto (the upload)',
              ProGalleryProvider(),
              salonReset,
              (s) => s.addPhoto('p1', '/tmp/x.jpg'),
              () => held.land(ApiResponse.success('https://cdn/x.jpg')),
            );
            verifyNever(() => pro.updateGalleryPhotos(any(), any()));
          },
        );

        test('addPhoto: the save answered after the reset', () async {
          when(
            () => uploads.uploadImage(
              source: any(named: 'source'),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((_) async => ApiResponse.success('https://cdn/x.jpg'));
          final held = Completer<ApiResponse<List<String>>>();
          when(
            () => pro.updateGalleryPhotos(any(), any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'addPhoto (the save)',
            ProGalleryProvider(),
            salonReset,
            (s) => s.addPhoto('p1', '/tmp/x.jpg'),
            () => held.land(refused()),
          );
        });

        test('an upload\'s progress after the reset says nothing', () async {
          void Function(double)? progress;
          final held = Completer<ApiResponse<String>>();
          when(
            () => uploads.uploadImage(
              source: any(named: 'source'),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((call) {
            progress =
                call.namedArguments[#onProgress] as void Function(double)?;
            return held.future;
          });
          await expectIgnored(
            'addPhoto progress',
            ProGalleryProvider(),
            salonReset,
            (s) => s.addPhoto('p1', '/tmp/x.jpg'),
            () {
              progress!(0.5);
              held.land(refused());
            },
          );
        });

        for (final (name, run)
            in <(String, Future<bool> Function(ProGalleryProvider))>[
              ('movePhoto', (s) => s.movePhoto('p1', 0, 1)),
              ('setCover', (s) => s.setCover('p1', 1)),
              (
                'restorePhotoAt',
                (s) => s.restorePhotoAt('p1', 0, 'https://cdn/r.jpg'),
              ),
              ('removePhoto', (s) => s.removePhoto('p1', 0)),
            ]) {
          test(name, () async {
            // Two photos to move, cover or remove: the load answers first.
            when(() => pro.getGalleryPhotos(any())).thenAnswer(
              (_) async =>
                  ApiResponse.success(const ['https://a', 'https://b']),
            );
            final held = Completer<ApiResponse<List<String>>>();
            when(
              () => pro.updateGalleryPhotos(any(), any()),
            ).thenAnswer((_) => held.future);
            final store = ProGalleryProvider();
            await store.load('p1');
            await expectIgnored(
              name,
              store,
              salonReset,
              run,
              () => held.land(refused()),
            );
          });
        }
      });

      group('ProOnboardingProvider', () {
        test('publish', () async {
          final held = Completer<ApiResponse<bool>>();
          when(() => pro.publishSalon(any())).thenAnswer((_) => held.future);
          await expectIgnored(
            'publish',
            ProOnboardingProvider(),
            salonReset,
            (s) => s.publish('p1'),
            () => held.land(refused()),
          );
        });

        // Its load is six reads in a row: whichever is out at the reset, its
        // answer writes nothing and nothing after it is asked for the previous
        // salon. (A refused read does not stop the chain — `read` keeps going.)
        final owner = MockData.providerUsers.first;
        for (var point = 0; point < 6; point++) {
          test(
            'load: read ${point + 1} of 6 answered after the reset',
            () async {
              final gate = Completer<void>();
              var asked = 0;
              Future<ApiResponse<T>> at<T>(int i) {
                asked = i + 1;
                return i == point
                    ? gate.future.then((_) => refused<T>())
                    : Future.value(refused<T>());
              }

              when(
                () => pro.getProviderServices(any()),
              ).thenAnswer((_) => at(0));
              when(() => artists.getArtists(any())).thenAnswer((_) => at(1));
              when(
                () => pro.getProviderAvailability(any()),
              ).thenAnswer((_) => at(2));
              when(() => pro.getDepositPolicy(any())).thenAnswer((_) => at(3));
              when(
                () => pro.getMyProvider(salonId: any(named: 'salonId')),
              ).thenAnswer((_) => at(4));
              when(() => kyc.getKycStatus(any())).thenAnswer((_) => at(5));
              await expectIgnored(
                'onboarding load, read ${point + 1}',
                ProOnboardingProvider(),
                salonReset,
                (s) => s.load(owner, salonId: 'p1'),
                () => gate.land(null),
              );
              expect(
                asked,
                point + 1,
                reason:
                    'a read after the reset was still asked for the old salon',
              );
            },
          );
        }
      });

      group('ProReviewsProvider', () {
        test('loadReviews', () async {
          final held = Completer<ApiResponse<MyReviews>>();
          when(
            () => pro.getMyReviews(
              page: any(named: 'page'),
              pageSize: any(named: 'pageSize'),
            ),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'loadReviews',
            ProReviewsProvider(),
            salonReset,
            (s) => s.loadReviews('p1'),
            () => held.land(refused()),
          );
        });
      });

      group('ProSalonProfileProvider', () {
        test('load', () async {
          final held = Completer<ApiResponse<MyProviderInfo>>();
          when(
            () => pro.getMyProvider(salonId: any(named: 'salonId')),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'load',
            ProSalonProfileProvider(),
            salonReset,
            (s) => s.load('p1'),
            () => held.land(refused()),
          );
        });

        test('save', () async {
          final held = Completer<ApiResponse<Provider>>();
          when(
            () => pro.updateSalonProfile(any(), any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'save',
            ProSalonProfileProvider(),
            salonReset,
            (s) => s.save('p1', const {'name': 'x'}),
            () => held.land(refused()),
          );
        });

        test(
          'uploadLogo: the upload answered after the reset saves nothing',
          () async {
            final held = Completer<ApiResponse<String>>();
            when(
              () => logos.uploadImage(
                source: any(named: 'source'),
                onProgress: any(named: 'onProgress'),
              ),
            ).thenAnswer((_) => held.future);
            when(
              () => pro.updateSalonProfile(any(), any()),
            ).thenAnswer((_) async => refused());
            await expectIgnored(
              'uploadLogo (the upload)',
              ProSalonProfileProvider(),
              salonReset,
              (s) => s.uploadLogo('p1', '/tmp/logo.png'),
              () => held.land(ApiResponse.success('https://cdn/logo.png')),
            );
            verifyNever(() => pro.updateSalonProfile(any(), any()));
          },
        );

        test('uploadLogo: the save answered after the reset', () async {
          when(
            () => logos.uploadImage(
              source: any(named: 'source'),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer(
            (_) async => ApiResponse.success('https://cdn/logo.png'),
          );
          final held = Completer<ApiResponse<Provider>>();
          when(
            () => pro.updateSalonProfile(any(), any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'uploadLogo (the save)',
            ProSalonProfileProvider(),
            salonReset,
            (s) => s.uploadLogo('p1', '/tmp/logo.png'),
            () => held.land(refused()),
          );
        });
      });

      group('ProServiceProvider', () {
        test('loadServices', () async {
          final held = Completer<ApiResponse<List<Service>>>();
          when(
            () => pro.getProviderServices(any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'loadServices',
            ProServiceProvider(),
            salonReset,
            (s) => s.loadServices('p1'),
            () => held.land(refused()),
          );
        });

        test('createService', () async {
          final held = Completer<ApiResponse<Service>>();
          when(
            () => pro.createService(any(), any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'createService',
            ProServiceProvider(),
            salonReset,
            (s) => s.createService('p1', const {}),
            () => held.land(refused()),
          );
        });

        test('updateService', () async {
          final held = Completer<ApiResponse<Service>>();
          when(
            () => pro.updateService(any(), any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'updateService',
            ProServiceProvider(),
            salonReset,
            (s) => s.updateService('s1', const {}),
            () => held.land(refused()),
          );
        });

        test('deleteService', () async {
          final held = Completer<ApiResponse<bool>>();
          when(() => pro.deleteService(any())).thenAnswer((_) => held.future);
          await expectIgnored(
            'deleteService',
            ProServiceProvider(),
            salonReset,
            (s) => s.deleteService('s1'),
            () => held.land(refused()),
          );
        });
      });

      group('ProSubscriptionProvider', () {
        test('load', () async {
          final held = Completer<ApiResponse<SalonSubscription>>();
          when(
            () => subscriptions.getSalonSubscription(any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'load',
            ProSubscriptionProvider(),
            salonReset,
            (s) => s.load('p1'),
            () => held.land(refused()),
          );
        });
      });

      group('ProTeamProvider', () {
        test('load', () async {
          final held = Completer<ApiResponse<List<TeamMember>>>();
          when(() => team.getMembers()).thenAnswer((_) => held.future);
          await expectIgnored(
            'load',
            ProTeamProvider(),
            salonReset,
            (s) => s.load(),
            () => held.land(refused()),
          );
        });

        test('invite', () async {
          final held = Completer<ApiResponse<TeamMember>>();
          when(
            () => team.inviteMember(
              email: any(named: 'email'),
              role: any(named: 'role'),
              artistId: any(named: 'artistId'),
              idempotencyKey: any(named: 'idempotencyKey'),
            ),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'invite',
            ProTeamProvider(),
            salonReset,
            (s) => s.invite(email: 'x@myweli.test', role: TeamRole.staff),
            () => held.land(refused()),
          );
        });

        for (final (name, stub, run)
            in <
              (
                String,
                void Function(Future<ApiResponse<TeamMember>>),
                Future<bool> Function(ProTeamProvider),
              )
            >[
              (
                'changeRole',
                (f) => when(
                  () => team.changeRole(
                    any(),
                    role: any(named: 'role'),
                    artistId: any(named: 'artistId'),
                  ),
                ).thenAnswer((_) => f),
                (s) => s.changeRole('m1', role: TeamRole.manager),
              ),
              (
                'revoke',
                (f) =>
                    when(() => team.revokeMember(any())).thenAnswer((_) => f),
                (s) => s.revoke('m1'),
              ),
              (
                'resend',
                (f) => when(
                  () => team.resendInvitation(any()),
                ).thenAnswer((_) => f),
                (s) => s.resend('m1'),
              ),
            ]) {
          test(name, () async {
            final held = Completer<ApiResponse<TeamMember>>();
            stub(held.future);
            await expectIgnored(
              name,
              ProTeamProvider(),
              salonReset,
              run,
              () => held.land(refused()),
            );
          });
        }

        test('loadMyInvitations', () async {
          final held = Completer<ApiResponse<List<TeamInvitation>>>();
          when(() => team.getMyInvitations()).thenAnswer((_) => held.future);
          await expectIgnored(
            'loadMyInvitations',
            ProTeamProvider(),
            salonReset,
            (s) => s.loadMyInvitations(),
            () => held.land(refused()),
          );
        });

        test('acceptMyInvitation', () async {
          final held = Completer<ApiResponse<TeamMember>>();
          when(
            () => team.acceptInvitation(any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'acceptMyInvitation',
            ProTeamProvider(),
            salonReset,
            (s) => s.acceptMyInvitation('i1'),
            () => held.land(refused()),
          );
        });

        test('declineMyInvitation', () async {
          final held = Completer<ApiResponse<bool>>();
          when(
            () => team.declineInvitation(any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'declineMyInvitation',
            ProTeamProvider(),
            salonReset,
            (s) => s.declineMyInvitation('i1'),
            () => held.land(refused()),
          );
        });
      });

      group('ProClientsProvider', () {
        test('load', () async {
          final held = Completer<ApiResponse<SalonClientsPage>>();
          when(
            () => clients.listClients(
              any(),
              query: any(named: 'query'),
              tag: any(named: 'tag'),
              page: any(named: 'page'),
              pageSize: any(named: 'pageSize'),
            ),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'load',
            ProClientsProvider(),
            salonReset,
            (s) => s.load('p1'),
            () => held.land(refused()),
          );
        });

        test('loadMore', () async {
          // A first page of one client out of two, so there is more to load.
          final page = (await MockProClientsService().listClients(
            'provider1',
            pageSize: 1,
          )).data!;
          expect(
            page.total,
            greaterThan(page.items.length),
            reason: 'scenario',
          );
          final held = Completer<ApiResponse<SalonClientsPage>>();
          var call = 0;
          when(
            () => clients.listClients(
              any(),
              query: any(named: 'query'),
              tag: any(named: 'tag'),
              page: any(named: 'page'),
              pageSize: any(named: 'pageSize'),
            ),
          ).thenAnswer(
            (_) => call++ == 0
                ? Future.value(ApiResponse.success(page))
                : held.future,
          );
          final store = ProClientsProvider();
          await store.load('p1');
          await expectIgnored(
            'loadMore',
            store,
            salonReset,
            (s) => s.loadMore('p1'),
            () => held.land(refused()),
          );
        });

        test('addClient', () async {
          final held = Completer<ApiResponse<String>>();
          when(
            () => clients.addClient(
              any(),
              name: any(named: 'name'),
              phone: any(named: 'phone'),
              note: any(named: 'note'),
            ),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'addClient',
            ProClientsProvider(),
            salonReset,
            (s) => s.addClient('p1', name: 'Awa', phone: '+2250700000001'),
            () => held.land(refused()),
          );
        });

        for (final point in ['the card', 'its visits']) {
          test('loadCard: $point answered after the reset', () async {
            final card = (await MockProClientsService().getCard(
              'provider1',
              'sc1',
            )).data!;
            final gate = Completer<void>();
            when(() => clients.getCard(any(), any())).thenAnswer(
              (_) => point == 'the card'
                  ? gate.future.then((_) => ApiResponse.success(card))
                  : Future.value(ApiResponse.success(card)),
            );
            when(
              () => clients.getVisits(any(), any(), page: any(named: 'page')),
            ).thenAnswer(
              (_) => gate.future.then(
                (_) => ApiResponse<List<Appointment>>.success(const []),
              ),
            );
            await expectIgnored(
              'loadCard ($point)',
              ProClientsProvider(),
              salonReset,
              (s) => s.loadCard('p1', 'sc1'),
              () => gate.land(null),
            );
          });
        }

        // The writes on a card: the next account has opened ITS card by the
        // time the previous one's answer lands.
        for (final (name, stub, run)
            in <
              (
                String,
                void Function(SalonClientCard, Completer<void>),
                Future<Object?> Function(ProClientsProvider),
              )
            >[
              (
                'updateTags',
                (card, gate) =>
                    when(
                      () => clients.updateTags(any(), any(), any()),
                    ).thenAnswer(
                      (_) => gate.future.then(
                        (_) => ApiResponse.success(card.client),
                      ),
                    ),
                (s) => s.updateTags('p1', 'sc1', const ['VIP']),
              ),
              (
                'addNote',
                (card, gate) =>
                    when(
                      () => clients.addNote(
                        any(),
                        any(),
                        any(),
                        idempotencyKey: any(named: 'idempotencyKey'),
                      ),
                    ).thenAnswer(
                      (_) => gate.future.then(
                        (_) => ApiResponse.success(
                          card.notes.isEmpty
                              ? SalonClientNote(
                                  id: 'n9',
                                  authorName: 'A',
                                  body: 'une note de A',
                                  createdAt: DateTime(2026, 10),
                                )
                              : card.notes.first,
                        ),
                      ),
                    ),
                (s) => s.addNote('p1', 'sc1', 'une note de A'),
              ),
              (
                'deleteNote',
                (card, gate) =>
                    when(
                      () => clients.deleteNote(any(), any(), any()),
                    ).thenAnswer(
                      (_) => gate.future.then((_) => ApiResponse.success(true)),
                    ),
                (s) => s.deleteNote('p1', 'sc1', 'note1'),
              ),
            ]) {
          test(
            '$name answered after the next account opened its card',
            () async {
              final card = (await MockProClientsService().getCard(
                'provider1',
                'sc1',
              )).data!;
              when(
                () => clients.getCard(any(), any()),
              ).thenAnswer((_) async => ApiResponse.success(card));
              when(
                () => clients.getVisits(any(), any(), page: any(named: 'page')),
              ).thenAnswer((_) async => ApiResponse.success(const []));
              final gate = Completer<void>();
              stub(card, gate);
              final store = ProClientsProvider();
              await store.loadCard('p1', 'sc1');

              final pending = run(store);
              await pumpEventQueue();
              store.resetForSalonSwitch();
              await store.loadCard('p1', 'sc1'); // the next account's card
              final before = store.card;
              var notified = 0;
              store.addListener(() => notified++);
              gate.land(null);
              try {
                await pending;
              } catch (_) {
                // updateTags, addNote and deleteNote have no `catch`.
              }
              await pumpEventQueue();

              expect(
                notified,
                0,
                reason: '$name rebuilt the next account\'s card',
              );
              expect(store.card, same(before));
            },
          );
        }

        // A refused number writes nothing anyway; a changed one rewrites the
        // card and the list row — the next account's, by then.
        for (final point in ['the change', 'the visits']) {
          test('updatePhone: $point answered after the reset', () async {
            final card = (await MockProClientsService().getCard(
              'provider1',
              'sc1',
            )).data!;
            final gate = Completer<void>();
            when(() => clients.updatePhone(any(), any(), any())).thenAnswer(
              (_) => point == 'the change'
                  ? gate.future.then(
                      (_) => ApiResponse.success(
                        SalonClientPhoneChange.changed(card),
                      ),
                    )
                  : Future.value(
                      ApiResponse.success(SalonClientPhoneChange.changed(card)),
                    ),
            );
            when(
              () => clients.getVisits(any(), any(), page: any(named: 'page')),
            ).thenAnswer(
              (_) => point == 'the visits'
                  ? gate.future.then(
                      (_) => ApiResponse<List<Appointment>>.success(const []),
                    )
                  : Future.value(
                      ApiResponse<List<Appointment>>.success(const []),
                    ),
            );
            await expectIgnored(
              'updatePhone ($point)',
              ProClientsProvider(),
              salonReset,
              (s) => s.updatePhone('p1', 'sc1', '+2250700000002'),
              () => gate.land(null),
            );
          });
        }

        test('the reset forgets the open card', () async {
          final card = (await MockProClientsService().getCard(
            'provider1',
            'sc1',
          )).data!;
          when(
            () => clients.getCard(any(), any()),
          ).thenAnswer((_) async => ApiResponse.success(card));
          when(
            () => clients.getVisits(any(), any(), page: any(named: 'page')),
          ).thenAnswer(
            (_) => MockProClientsService().getVisits('provider1', 'sc1'),
          );
          final store = ProClientsProvider();
          await store.loadCard('p1', 'sc1');
          expect(store.card, isNotNull, reason: 'the scenario');
          expect(store.visits, isNotEmpty, reason: 'the scenario');

          store.resetForSalonSwitch();

          expect(store.card, isNull);
          expect(store.cardClientId, isNull);
          expect(store.visits, isEmpty);
          expect(store.cardLoading, isFalse);
          expect(store.cardError, isNull);
        });
      });

      group('ProJournalProvider', () {
        test('an action answered after the reset', () async {
          final held = Completer<ApiResponse<bool>>();
          when(
            () => pro.acceptAppointment(any()),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'journal accept',
            ProJournalProvider(),
            salonReset,
            (s) => s.accept('a1'),
            () => held.land(refused()),
          );
        });

        // Its reads already drop a late answer by request number — and a load
        // moves that number too, so the actions get their own: a load started
        // while an action is out must NOT make the action's success look stale.
        test(
          'an action that succeeded keeps its effect across a load',
          () async {
            final day = JournalDay(
              date: '2026-11-02',
              artists: const [],
              appointments: [
                Appointment(
                  id: 'a1',
                  userId: 'u1',
                  providerId: 'p1',
                  serviceIds: const ['s1'],
                  appointmentDate: DateTime.utc(2026, 11, 2, 10),
                  status: AppointmentStatus.pending,
                  totalPrice: 10000,
                  depositAmount: 0,
                  balanceDue: 10000,
                  createdAt: DateTime(2026, 10),
                ),
              ],
            );
            when(
              () => pro.getJournalDay(any(), any()),
            ).thenAnswer((_) async => ApiResponse.success(day));
            final held = Completer<ApiResponse<bool>>();
            when(
              () => pro.acceptAppointment(any()),
            ).thenAnswer((_) => held.future);
            ProSalonScope.clear();
            final ear = ProSalonScope.track(_Ear());
            final store = ProJournalProvider();
            await store.load('p1', date: DateTime.utc(2026, 11, 2));

            final accepting = store.accept('a1');
            await store.refresh();
            held.complete(ApiResponse<bool>.success(true));

            expect(await accepting, isTrue);
            expect(
              ear.heard,
              ['a1'],
              reason:
                  'the accept was taken for a stale answer and not announced',
            );
            ProSalonScope.clear();
          },
        );
      });

      group('ProKycProvider (the account\'s)', () {
        test(
          'the reset forgets the documents, the status and the reason',
          () async {
            when(() => kyc.getKycStatus(any())).thenAnswer(
              (_) async => ApiResponse.success(
                KycStatus(
                  status: VerificationStatus.rejected,
                  rejectionReason: 'Pièce illisible',
                  documents: [
                    KycDocument(
                      type: KycDocumentType.idCard,
                      fileName: 'cni.jpg',
                      key: 'kyc/a/cni',
                      submittedAt: DateTime(2026, 10),
                    ),
                  ],
                ),
              ),
            );
            final store = ProKycProvider();
            await store.load('provider_user1');
            expect(store.documents, isNotEmpty, reason: 'the scenario');
            var notified = 0;
            store.addListener(() => notified++);

            store.resetForAccountChange();

            expect(store.documents, isEmpty);
            expect(store.status, VerificationStatus.pending);
            expect(store.rejectionReason, isNull);
            expect(store.loaded, isFalse);
            expect(store.loadFailed, isFalse);
            expect(store.error, isNull);
            expect(store.isLoading, isFalse);
            expect(store.isSubmitting, isFalse);
            expect(store.uploadingType, isNull);
            expect(notified, 1);
          },
        );

        test('load', () async {
          final held = Completer<ApiResponse<KycStatus>>();
          when(() => kyc.getKycStatus(any())).thenAnswer((_) => held.future);
          await expectIgnored(
            'kyc load',
            ProKycProvider(),
            (s) => s.resetForAccountChange(),
            (s) => s.load('provider_user1'),
            () => held.land(refused()),
          );
        });

        // A's identity document, answered after B signed in, would join B's
        // set — and go out with B's next « Envoyer ».
        test('addDocument: A\'s document never joins B\'s set', () async {
          final held = Completer<ApiResponse<String>>();
          when(
            () => kyc.uploadDocument(
              source: any(named: 'source'),
              contentType: any(named: 'contentType'),
            ),
          ).thenAnswer((_) => held.future);
          final store = ProKycProvider();
          await expectIgnored(
            'kyc addDocument',
            store,
            (s) => s.resetForAccountChange(),
            (s) => s.addDocument(
              KycDocumentType.idCard,
              '/a/cni.jpg',
              'image/jpeg',
            ),
            () => held.land(ApiResponse.success('kyc/a/cni')),
          );
          expect(store.documents, isEmpty);
        });

        test('submit', () async {
          final held = Completer<ApiResponse<KycStatus>>();
          when(
            () => kyc.submitKyc(
              providerUserId: any(named: 'providerUserId'),
              documents: any(named: 'documents'),
            ),
          ).thenAnswer((_) => held.future);
          await expectIgnored(
            'kyc submit',
            ProKycProvider(),
            (s) => s.resetForAccountChange(),
            (s) => s.submit('provider_user1'),
            () => held.land(refused()),
          );
        });
      });
    });
  }

  // Each line of a reset, in a state where its field is NOT already at rest
  // — a reset checked on a quiet store proves nothing about it.
  group('the resets forget everything, not only the data', () {
    test(
      'KYC: a failed read, a read out, a submission out, an upload out',
      () async {
        final store = ProKycProvider();
        when(() => kyc.getKycStatus(any())).thenAnswer((_) async => refused());
        await store.load('provider_user1');
        expect(store.loadFailed, isTrue, reason: 'the scenario');
        store.resetForAccountChange();
        expect(store.loadFailed, isFalse);
        expect(store.error, isNull);

        when(
          () => kyc.getKycStatus(any()),
        ).thenAnswer((_) => Completer<ApiResponse<KycStatus>>().future);
        unawaited(store.load('provider_user1'));
        expect(store.isLoading, isTrue, reason: 'the scenario');
        store.resetForAccountChange();
        expect(store.isLoading, isFalse);

        when(
          () => kyc.submitKyc(
            providerUserId: any(named: 'providerUserId'),
            documents: any(named: 'documents'),
          ),
        ).thenAnswer((_) => Completer<ApiResponse<KycStatus>>().future);
        unawaited(store.submit('provider_user1'));
        expect(store.isSubmitting, isTrue, reason: 'the scenario');
        store.resetForAccountChange();
        expect(store.isSubmitting, isFalse);

        when(
          () => kyc.uploadDocument(
            source: any(named: 'source'),
            contentType: any(named: 'contentType'),
          ),
        ).thenAnswer((_) => Completer<ApiResponse<String>>().future);
        unawaited(
          store.addDocument(KycDocumentType.selfie, '/s.jpg', 'image/jpeg'),
        );
        expect(store.uploadingType, KycDocumentType.selfie, reason: 'scenario');
        store.resetForAccountChange();
        expect(store.uploadingType, isNull);
      },
    );

    test(
      'clients: a card loading, a card not found, a duplicate add',
      () async {
        final store = ProClientsProvider();
        when(
          () => clients.getCard(any(), any()),
        ).thenAnswer((_) => Completer<ApiResponse<SalonClientCard>>().future);
        unawaited(store.loadCard('p1', 'sc1'));
        expect(store.cardLoading, isTrue, reason: 'the scenario');
        store.resetForSalonSwitch();
        expect(store.cardLoading, isFalse);

        when(() => clients.getCard(any(), any())).thenAnswer(
          (_) async => ApiResponse<SalonClientCard>.error(
            'Introuvable',
            code: 'not_found',
          ),
        );
        await store.loadCard('p1', 'sc1');
        expect(store.cardNotFound, isTrue, reason: 'the scenario');
        store.resetForSalonSwitch();
        expect(store.cardError, isNull);
        expect(store.cardNotFound, isFalse);

        when(
          () => clients.addClient(
            any(),
            name: any(named: 'name'),
            phone: any(named: 'phone'),
            note: any(named: 'note'),
          ),
        ).thenAnswer(
          (_) async => const ApiResponse<String>(
            success: false,
            data: 'sc1',
            error: 'Déjà là',
            code: 'client_exists',
          ),
        );
        await store.addClient('p1', name: 'Awa', phone: '+2250700000001');
        expect(store.lastAddWasDuplicate, isTrue, reason: 'the scenario');
        store.resetForSalonSwitch();
        expect(store.lastAddWasDuplicate, isFalse);
      },
    );
  });
}
