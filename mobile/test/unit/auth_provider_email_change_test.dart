import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/access/account_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/email_change_request.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/services/interfaces/auth_service_interface.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';

class _MockAuthService extends Mock implements AuthServiceInterface {}

User _user(String id, {String? email}) => User(
  id: id,
  email: email ?? '$id@exemple.ci',
  emailVerified: true,
  createdAt: DateTime(2026),
);

const _sent = EmailChangeRequest(
  expiresInSeconds: 300,
  currentCodeSent: true,
  devCode: '111111',
  currentDevCode: '222222',
);

/// `AuthProvider`'s address change (B16.3b — account-email-change.md §5.4):
/// what it keeps of each answer, and the account guard — an answer that
/// arrives once another account is signed in, or none, is the previous
/// account's, and is dropped (the guard `updateUser` has, §5.4's « Every
/// state »).
void main() {
  late _MockAuthService auth;
  late StreamController<void> sessionEnded;

  setUpAll(() {
    auth = _MockAuthService();
    serviceLocator
      ..authService = auth
      ..pushRegistration = PushRegistration(
        push: MockPushNotificationService(),
        devices: MockDeviceRegistrationService(),
      );
  });

  setUp(() {
    AccountScope.clear();
    reset(auth);
    sessionEnded = StreamController<void>.broadcast();
    when(() => auth.sessionEnded).thenAnswer((_) => sessionEnded.stream);
    when(() => auth.getCurrentUser()).thenAnswer((_) async => null);
    when(() => auth.logout()).thenAnswer((_) async {});
  });

  tearDown(() => sessionEnded.close());

  Future<AuthProvider> signedInAs(String id) async {
    when(
      () => auth.verifyEmailOtp(any(), any()),
    ).thenAnswer((_) async => ApiResponse.success(_user(id)));
    final provider = AuthProvider();
    await pumpEventQueue();
    expect(await provider.verifyEmailOtp('$id@exemple.ci', '123456'), isTrue);
    return provider;
  }

  test('a sent request is kept: the second code, the dev codes', () async {
    final provider = await signedInAs('a');
    when(
      () => auth.requestEmailChange(any()),
    ).thenAnswer((_) async => ApiResponse.success(_sent));

    expect(await provider.requestEmailChange('n@exemple.ci'), isTrue);

    expect(provider.emailChange, _sent);
    expect(provider.emailChangeErrorCode, isNull);
    expect(provider.isLoading, isFalse);
  });

  test('a refusal keeps its code and its words', () async {
    final provider = await signedInAs('a');
    when(() => auth.requestEmailChange(any())).thenAnswer(
      (_) async => ApiResponse.error(
        'C’est déjà votre adresse.',
        code: 'email_unchanged',
      ),
    );

    expect(await provider.requestEmailChange('a@exemple.ci'), isFalse);

    expect(provider.emailChangeErrorCode, 'email_unchanged');
    expect(provider.error, 'C’est déjà votre adresse.');
  });

  test(
    'a confirmed change: the answered account, and the request spent',
    () async {
      final provider = await signedInAs('a');
      when(
        () => auth.requestEmailChange(any()),
      ).thenAnswer((_) async => ApiResponse.success(_sent));
      await provider.requestEmailChange('n@exemple.ci');
      when(
        () => auth.confirmEmailChange(
          any(),
          any(),
          currentCode: any(named: 'currentCode'),
        ),
      ).thenAnswer(
        (_) async => ApiResponse.success(_user('a', email: 'n@exemple.ci')),
      );

      expect(
        await provider.confirmEmailChange(
          'n@exemple.ci',
          '111111',
          currentCode: '222222',
        ),
        isTrue,
      );

      expect(provider.user!.email, 'n@exemple.ci');
      expect(provider.emailChange, isNull);
      verify(
        () => auth.confirmEmailChange(
          'n@exemple.ci',
          '111111',
          currentCode: '222222',
        ),
      ).called(1);
    },
  );

  test(
    'a confirmation answered after a sign-out does not sign A back in',
    () async {
      final provider = await signedInAs('a');
      final answer = Completer<ApiResponse<User>>();
      when(
        () => auth.confirmEmailChange(
          any(),
          any(),
          currentCode: any(named: 'currentCode'),
        ),
      ).thenAnswer((_) => answer.future);

      final confirming = provider.confirmEmailChange('n@exemple.ci', '111111');
      await provider.logout();
      answer.complete(ApiResponse.success(_user('a', email: 'n@exemple.ci')));

      expect(await confirming, isFalse);
      expect(provider.user, isNull, reason: 'A\'s answer, for nobody');
      expect(provider.isLoading, isFalse);
    },
  );

  test('a confirmation answered once B is in never lands on B', () async {
    final provider = await signedInAs('a');
    final answer = Completer<ApiResponse<User>>();
    when(
      () => auth.confirmEmailChange(
        any(),
        any(),
        currentCode: any(named: 'currentCode'),
      ),
    ).thenAnswer((_) => answer.future);

    final confirming = provider.confirmEmailChange('n@exemple.ci', '111111');
    when(
      () => auth.verifyEmailOtp(any(), any()),
    ).thenAnswer((_) async => ApiResponse.success(_user('b')));
    await provider.verifyEmailOtp('b@exemple.ci', '123456');
    answer.complete(ApiResponse.success(_user('a', email: 'n@exemple.ci')));

    expect(await confirming, isFalse);
    expect(provider.user!.id, 'b');
    expect(provider.user!.email, 'b@exemple.ci');
  });

  test('a request answered once B is in is not kept for B', () async {
    final provider = await signedInAs('a');
    final answer = Completer<ApiResponse<EmailChangeRequest>>();
    when(() => auth.requestEmailChange(any())).thenAnswer((_) => answer.future);

    final sending = provider.requestEmailChange('n@exemple.ci');
    when(
      () => auth.verifyEmailOtp(any(), any()),
    ).thenAnswer((_) async => ApiResponse.success(_user('b')));
    await provider.verifyEmailOtp('b@exemple.ci', '123456');
    answer.complete(ApiResponse.success(_sent));

    expect(await sending, isFalse);
    expect(provider.emailChange, isNull);
  });

  test('another account signing in drops the request in hand', () async {
    final provider = await signedInAs('a');
    when(
      () => auth.requestEmailChange(any()),
    ).thenAnswer((_) async => ApiResponse.success(_sent));
    await provider.requestEmailChange('n@exemple.ci');
    expect(provider.emailChange, isNotNull);

    when(
      () => auth.verifyEmailOtp(any(), any()),
    ).thenAnswer((_) async => ApiResponse.success(_user('b')));
    await provider.verifyEmailOtp('b@exemple.ci', '123456');

    expect(provider.emailChange, isNull);
  });

  test('signed out: nothing is asked', () async {
    final provider = AuthProvider();
    await pumpEventQueue();
    expect(await provider.requestEmailChange('n@exemple.ci'), isFalse);
    verifyNever(() => auth.requestEmailChange(any()));
  });
}
