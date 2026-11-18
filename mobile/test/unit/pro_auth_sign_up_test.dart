import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/router/pro_router.dart';
import 'package:myweli/models/pro_sign_up_fields.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/models/provider_login_result.dart';
import 'package:myweli/models/provider_sign_up_result.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';

import '../support/rejoin.dart';

/// The Android sign-up in `ProAuthProvider` and the mock it runs on
/// (docs/design/pro-android-signup.md §2.5, §5.2, §8.2 « Unit, the
/// provider » and « Unit, the mock »).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mockAuth = MockAuthService();
  // A mock sign-up adds to the shared mock world: each test starts from it
  // as it was.
  late final List<ProviderUser> seededAccounts;
  late final List<Provider> seededSalons;

  setUpAll(() {
    seededAccounts = List.of(MockData.providerUsers);
    seededSalons = List.of(MockData.providers);
    serviceLocator
      ..authService = mockAuth
      ..proService = MockProService()
      ..proTeamService = MockProTeamService()
      ..proPushRegistration = PushRegistration(
        push: MockPushNotificationService(),
        devices: MockDeviceRegistrationService(),
      );
  });

  var fresh = 0;

  /// An address no account and no invitation has: each test its own, since
  /// a mock sign-up adds to the shared mock world.
  String freshEmail() => 'nouveau${fresh++}@salon.test';

  setUp(() async {
    MockData.resetTeam();
    MockData.providerUsers
      ..clear()
      ..addAll(seededAccounts);
    MockData.providers
      ..clear()
      ..addAll(seededSalons);
    mockAuth.proGoogleEmail = MockAuthService.mockProGoogleEmail;
    await mockAuth.logoutProvider();
    // The provider navigates on its own (sign-out, the rejoin gate).
    ProRouter.router.go('/pro/splash');
  });

  ProSignUpFields fields({String phone = '+2250707010101'}) => ProSignUpFields(
    businessName: 'Salon Awa',
    businessType: BusinessType.spa,
    phoneNumber: phone,
    address: 'Rue des Jardins',
  );

  Future<ProAuthProvider> ready() async {
    final auth = ProAuthProvider();
    await auth.ready;
    return auth;
  }

  /// A sign-in that answered `provider_not_found` — what E2 and E3 leave.
  Future<void> refusedSignIn(ProAuthProvider auth) async {
    mockAuth.proGoogleEmail = freshEmail();
    expect(await auth.signInWithGoogle(), isFalse);
    expect(auth.errorCode, 'provider_not_found');
  }

  group('created', () {
    test('Google, no account: the account, its draft salon, OWNER', () async {
      final auth = await ready();
      final email = freshEmail();
      mockAuth.proGoogleEmail = email;
      final salons = MockData.providers.length;

      final result = await auth.signUpSalonWithGoogle(fields());

      final created = result as ProviderSignUpCreated;
      expect(auth.isAuthenticated, isTrue);
      expect(created.provider.email, email);
      expect(MockData.providers, hasLength(salons + 1));
      final salonId = created.provider.providerId!;
      expect(MockData.salonStatusOf(salonId), 'draft', reason: 'never live');
      expect(auth.membership?.role, TeamRole.owner);
      expect(auth.membership?.salonId, salonId);
    });

    test('e-mail: the code, the check, then register', () async {
      final auth = await ready();
      final email = freshEmail();
      await auth.requestEmailOtp(email);

      final result = await auth.signUpSalonWithEmail(
        email,
        auth.emailDevCode!,
        fields(),
      );

      expect(result, isA<ProviderSignUpCreated>());
      expect(auth.isAuthenticated, isTrue);
      expect(auth.membership?.role, TeamRole.owner);
    });

    test(
      'clears the sign-in\'s feedback (no stale « Aucun compte »)',
      () async {
        final auth = await ready();
        await refusedSignIn(auth);

        await auth.signUpSalonWithGoogle(fields());

        expect(auth.error, isNull);
        expect(auth.errorCode, isNull);
      },
    );
  });

  test('signed in: an account exists, nothing is created (S3)', () async {
    final auth = await ready();
    const email = 'jean@salon-excellence.test';
    await auth.requestEmailOtp(email);
    final salons = MockData.providers.length;

    final result = await auth.signUpSalonWithEmail(
      email,
      auth.emailDevCode!,
      fields(),
    );

    expect(result, isA<ProviderSignUpSignedIn>());
    expect(auth.isAuthenticated, isTrue);
    expect(MockData.providers, hasLength(salons));
  });

  test('a former member with nothing pending: signed out, the notice '
      'left for the sign-in (S3b)', () async {
    final auth = await ready();
    final email = freshEmail();
    bareRevokedAccount(email);
    mockAuth.proGoogleEmail = email;

    final result = await auth.signUpSalonWithGoogle(fields());

    expect(result, isA<ProviderSignUpEnded>());
    expect(auth.isAuthenticated, isFalse);
    expect(auth.consumeRevokedNotice(), isNotNull);
  });

  group('invited (S4)', () {
    test('holds the invitations and the proof that accepts them', () async {
      final auth = await ready();
      await refusedSignIn(auth);
      // The seeded e-mail invitee: its card has a roster row to activate.
      const email = 'invitee@myweli.test';
      await auth.requestEmailOtp(email);

      final result = await auth.signUpSalonWithEmail(
        email,
        auth.emailDevCode!,
        fields(),
      );

      expect(result, isA<ProviderSignUpInvited>());
      expect(auth.hasPendingInvitations, isTrue);
      expect(auth.errorCode, isNull, reason: 'the 202 clears the feedback');
      final id = auth.pendingInvitations.first.id;
      expect(await auth.acceptPendingInvitation(id), isTrue);
      expect(auth.isAuthenticated, isTrue);
    });

    test('« Créer plutôt mon propre salon »: register with the held proof; '
        'its 201 drops what was held, the server keeps them', () async {
      final auth = await ready();
      await auth.signUpSalonWithGoogle(fields());
      final pending = List.of(
        MockData.teamInvitations[MockAuthService.mockProGoogleEmail]!,
      );
      expect(pending, isNotEmpty);

      final result = await auth.createOwnSalonInstead(fields());

      expect(result, isA<ProviderSignUpCreated>());
      expect(auth.hasPendingInvitations, isFalse);
      expect(auth.isAuthenticated, isTrue);
      expect(
        MockData.teamInvitations[MockAuthService.mockProGoogleEmail],
        pending,
        reason: 'the invitations stay pending on the server',
      );
    });

    test(
      'a refusal keeps what was held, so the choice is made again',
      () async {
        final auth = await ready();
        await auth.signUpSalonWithGoogle(fields());

        final refused = await auth.createOwnSalonInstead(fields(phone: '+225'));

        final failure = refused as ProviderSignUpFailure;
        expect(failure.code, 'invalid_phone');
        expect(failure.stage, ProSignUpStage.register);
        expect(auth.hasPendingInvitations, isTrue);
        expect(auth.isAuthenticated, isFalse);

        expect(
          await auth.createOwnSalonInstead(fields()),
          isA<ProviderSignUpCreated>(),
        );
      },
    );

    test('a new code for the same choice registers with it', () async {
      final auth = await ready();
      const email = 'invitee@myweli.test';
      await auth.requestEmailOtp(email);
      final first = auth.emailDevCode!;
      expect(
        await auth.signUpSalonWithEmail(email, first, fields()),
        isA<ProviderSignUpInvited>(),
      );
      await auth.requestEmailOtp(email);

      final result = await auth.createOwnSalonInstead(
        fields(),
        proof: EmailOtpInvitationProof(email, auth.emailDevCode!),
      );

      expect(result, isA<ProviderSignUpCreated>());
      expect(auth.hasPendingInvitations, isFalse);
    });

    test('nothing held: a failure, nothing created', () async {
      final auth = await ready();
      final salons = MockData.providers.length;

      final result = await auth.createOwnSalonInstead(fields());

      expect(result, isA<ProviderSignUpFailure>());
      expect(MockData.providers, hasLength(salons));
    });
  });

  test('a failure leaves the sign-in\'s fields untouched', () async {
    final auth = await ready();
    await refusedSignIn(auth);
    final before = (auth.error, auth.errorCode);

    final result = await auth.signUpSalonWithGoogle(fields(phone: '+225'));

    expect((result as ProviderSignUpFailure).code, 'invalid_phone');
    expect((auth.error, auth.errorCode), before);
    expect(auth.isLoading, isFalse);
  });

  group('the mock', () {
    test('answers after its latency, not synchronously', () async {
      var done = false;
      final future = mockAuth
          .signUpProviderWithGoogle(fields())
          .then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      await future;
    });

    test('Google\'s identity is settable', () async {
      mockAuth.proGoogleEmail = freshEmail();
      expect(
        await mockAuth.signUpProviderWithGoogle(fields()),
        isA<ProviderSignUpCreated>(),
      );
      mockAuth.proGoogleEmail = MockAuthService.mockProGoogleEmail;
      expect(
        await mockAuth.signUpProviderWithGoogle(fields()),
        isA<ProviderSignUpInvited>(),
        reason: 'the default identity has a seeded invitation',
      );
    });

    test('register checks the fields first, in the server\'s order', () async {
      Future<String?> code(ProSignUpFields f) async {
        final r = await mockAuth.registerProvider(
          GoogleInvitationProof('t'),
          f,
        );
        return (r as ProviderSignUpFailure).code;
      }

      mockAuth.proGoogleEmail = freshEmail();
      expect(
        await code(
          const ProSignUpFields(
            businessName: ' ',
            businessType: BusinessType.spa,
            phoneNumber: '+2250707010101',
            address: 'x',
          ),
        ),
        'invalid_input',
      );
      expect(
        await code(
          ProSignUpFields(
            businessName: '💇' * 121,
            businessType: BusinessType.spa,
            phoneNumber: '+2250707010101',
            address: 'x',
          ),
        ),
        'invalid_input',
        reason: '121 code points',
      );
      expect(await code(fields(phone: '0707')), 'invalid_phone');
      expect(
        await code(
          const ProSignUpFields(
            businessName: 'A',
            businessType: BusinessType.spa,
            phoneNumber: '+2250707010101',
            address: 'x',
            areaId: 'dakar',
          ),
        ),
        'invalid_area',
      );
    });

    test('register refuses an identity that has an account', () async {
      mockAuth.proGoogleEmail = 'jean@salon-excellence.test';
      final r = await mockAuth.registerProvider(
        const GoogleInvitationProof('t'),
        fields(),
      );
      expect((r as ProviderSignUpFailure).code, 'provider_exists');
    });

    test('a wrong code is refused at the check, the code kept', () async {
      final email = freshEmail();
      await mockAuth.requestProviderEmailOtp(email);
      final r = await mockAuth.signUpProviderWithEmail(
        email,
        '000000',
        fields(),
      );
      final failure = r as ProviderSignUpFailure;
      expect(
        (failure.code, failure.stage),
        ('otp_invalid', ProSignUpStage.check),
      );
      expect(
        await mockAuth.signUpProviderWithEmail(
          email,
          MockAuthService.demoOtp,
          fields(),
        ),
        isA<ProviderSignUpCreated>(),
      );
    });
  });
}
