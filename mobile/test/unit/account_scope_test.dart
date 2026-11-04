import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/access/account_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/services/interfaces/auth_service_interface.dart';
import 'package:myweli/services/interfaces/image_upload_service_interface.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';

class _MockAuthService extends Mock implements AuthServiceInterface {}

class _MockUploads extends Mock implements ImageUploadServiceInterface {}

/// A store that counts its resets — what every account-scoped store is to
/// [AccountScope].
class _Store extends ChangeNotifier implements AccountScoped {
  int resets = 0;

  @override
  void resetForAccountChange() {
    resets++;
    notifyListeners();
  }
}

class _Throwing implements AccountScoped {
  @override
  void resetForAccountChange() => throw StateError('boom');
}

User _user(String id) =>
    User(id: id, email: '$id@myweli.test', createdAt: DateTime(2026));

void main() {
  late _MockAuthService auth;
  late _MockUploads uploads;
  late StreamController<void> sessionEnded;

  setUpAll(() {
    auth = _MockAuthService();
    uploads = _MockUploads();
    serviceLocator
      ..authService = auth
      ..avatarImageUploadService = uploads
      ..pushRegistration = PushRegistration(
        push: MockPushNotificationService(),
        devices: MockDeviceRegistrationService(),
      );
  });

  setUp(() {
    AccountScope.clear();
    reset(auth);
    reset(uploads);
    sessionEnded = StreamController<void>.broadcast();
    when(() => auth.sessionEnded).thenAnswer((_) => sessionEnded.stream);
    when(() => auth.getCurrentUser()).thenAnswer((_) async => null);
    when(() => auth.logout()).thenAnswer((_) async {});
  });

  tearDown(() => sessionEnded.close());

  group('AccountScope', () {
    test('track hands the store back and resetAll resets each once', () {
      final a = _Store();
      final b = _Store();
      expect(AccountScope.track(a), same(a));
      AccountScope.track(b);

      AccountScope.resetAll();

      expect([a.resets, b.resets], [1, 1]);
      expect(AccountScope.isTracked(a), isTrue);
      expect(AccountScope.isTracked(_Store()), isFalse);
    });

    // §2.1: a sign-out that stopped at the third store would leave the next
    // three to the previous account.
    test('a store that throws does not stop the others', () {
      final before = _Store();
      final after = _Store();
      AccountScope.track(before);
      AccountScope.track(_Throwing());
      AccountScope.track(after);

      expect(AccountScope.resetAll, returnsNormally);
      expect([before.resets, after.resets], [1, 1]);
    });
  });

  group('AuthProvider — every way out of an account resets its stores', () {
    late _Store store;

    setUp(() => store = AccountScope.track(_Store()));

    Future<AuthProvider> signedInAs(String id) async {
      when(
        () => auth.verifyEmailOtp(any(), any()),
      ).thenAnswer((_) async => ApiResponse.success(_user(id)));
      final provider = AuthProvider();
      await pumpEventQueue();
      expect(
        await provider.verifyEmailOtp('$id@myweli.test', '123456'),
        isTrue,
      );
      return provider;
    }

    test('« Déconnexion »', () async {
      final provider = await signedInAs('a');
      final before = store.resets;

      await provider.logout();

      expect(provider.isAuthenticated, isFalse);
      expect(store.resets, before + 1);
    });

    test('a sign-out that failed keeps the account AND its data', () async {
      final provider = await signedInAs('a');
      final before = store.resets;
      when(() => auth.logout()).thenThrow(StateError('keychain'));

      await provider.logout();

      expect(provider.isAuthenticated, isTrue);
      expect(store.resets, before);
    });

    test('a phone sign-in resets too (dormant, kept for SMS)', () async {
      final provider = AuthProvider();
      await pumpEventQueue();
      final before = store.resets;
      when(
        () => auth.verifyOtp(any(), any()),
      ).thenAnswer((_) async => ApiResponse.success(_user('p')));

      await provider.verifyOtp('+2250700000000', '123456');

      expect(store.resets, before + 1);
    });

    test('« Supprimer mon compte » — done, and refused', () async {
      final provider = await signedInAs('a');
      final before = store.resets;
      when(() => auth.deleteAccount()).thenAnswer(
        (_) async => ApiResponse<void>.error(
          'Rendez-vous à venir',
          code: 'future_bookings',
        ),
      );
      expect(await provider.deleteAccount(), isFalse);
      expect(store.resets, before, reason: 'a refused deletion is no way out');

      when(
        () => auth.deleteAccount(),
      ).thenAnswer((_) async => ApiResponse.success(null));
      expect(await provider.deleteAccount(), isTrue);
      expect(store.resets, before + 1);
    });

    test(
      'a sign-in resets, the same account editing itself does not',
      () async {
        final provider = AuthProvider();
        await pumpEventQueue();
        final before = store.resets;
        when(
          () => auth.verifyEmailOtp(any(), any()),
        ).thenAnswer((_) async => ApiResponse.success(_user('b')));

        await provider.verifyEmailOtp('b@myweli.test', '123456');
        expect(store.resets, before + 1);

        when(
          () => auth.updateUser(
            name: any(named: 'name'),
            email: any(named: 'email'),
            avatarUrl: any(named: 'avatarUrl'),
            phone: any(named: 'phone'),
          ),
        ).thenAnswer((_) async => ApiResponse.success(_user('b')));
        await provider.updateUser(name: 'Awa');
        expect(store.resets, before + 1);
      },
    );

    // §2.2: no frame sees the new account with the old data — so a listener
    // of AuthProvider that reads the stores when it hears « signed out »
    // finds them already reset.
    test(
      'the stores are reset BEFORE the account change is announced',
      () async {
        final provider = await signedInAs('a');
        final before = store.resets;
        final heard = <({bool signedIn, int resets})>[];
        provider.addListener(
          () => heard.add((
            signedIn: provider.isAuthenticated,
            resets: store.resets,
          )),
        );

        await provider.logout();

        final signedOut = heard.where((h) => !h.signedIn);
        expect(signedOut, isNotEmpty);
        expect(signedOut.map((h) => h.resets), everyElement(before + 1));
      },
    );

    group('the session refused by the server (§2.4)', () {
      test('ends the account, resets the stores, and says so once', () async {
        final provider = await signedInAs('a');
        final before = store.resets;

        sessionEnded.add(null);
        await pumpEventQueue();

        expect(provider.isAuthenticated, isFalse);
        expect(store.resets, before + 1);
        expect(provider.consumeSessionEndedNotice(), isTrue);
        expect(
          provider.consumeSessionEndedNotice(),
          isFalse,
          reason: 'one notice per session refused',
        );
      });

      test('signed out already: nothing', () async {
        final provider = AuthProvider();
        await pumpEventQueue();
        final before = store.resets;

        sessionEnded.add(null);
        await pumpEventQueue();

        expect(store.resets, before);
        expect(provider.consumeSessionEndedNotice(), isFalse);
      });

      // §3: the sign-out clears the session itself; a refusal heard while it
      // runs is that same way out, not a second one with a notice.
      test('heard during a « Déconnexion »: one way out, no notice', () async {
        final provider = await signedInAs('a');
        final before = store.resets;
        final clearing = Completer<void>();
        when(() => auth.logout()).thenAnswer((_) => clearing.future);

        final out = provider.logout();
        await pumpEventQueue();
        sessionEnded.add(null);
        await pumpEventQueue();
        clearing.complete();
        await out;

        expect(store.resets, before + 1);
        expect(provider.consumeSessionEndedNotice(), isFalse);
      });

      // The deletion's own request is the one refused: the session is gone,
      // and the deletion fails with « Veuillez vous reconnecter. » — it must
      // not leave the app showing an account it no longer has.
      test('heard during a deletion that then fails: the account still '
          'ends, and says why', () async {
        final provider = await signedInAs('a');
        final before = store.resets;
        final refused = Completer<ApiResponse<void>>();
        when(() => auth.deleteAccount()).thenAnswer((_) => refused.future);

        final deleting = provider.deleteAccount();
        await pumpEventQueue();
        sessionEnded.add(null);
        await pumpEventQueue();
        refused.complete(
          ApiResponse<void>.error(
            'Veuillez vous reconnecter.',
            code: 'unauthorized',
          ),
        );

        expect(await deleting, isFalse);
        expect(provider.isAuthenticated, isFalse);
        expect(store.resets, before + 1);
        expect(provider.consumeSessionEndedNotice(), isTrue);
      });
    });

    group('an answer that comes back after the account changed', () {
      // §1: the photo A sent, finished after B signed in, was saved on B.
      test(
        'a profile photo finished after a sign-out is saved on nobody',
        () async {
          final provider = await signedInAs('a');
          final upload = Completer<ApiResponse<String>>();
          when(
            () => uploads.uploadImage(
              source: any(named: 'source'),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((_) => upload.future);

          final saving = provider.uploadAvatar('/tmp/a.jpg');
          await pumpEventQueue();
          await provider.logout();
          when(
            () => auth.verifyEmailOtp(any(), any()),
          ).thenAnswer((_) async => ApiResponse.success(_user('b')));
          await provider.verifyEmailOtp('b@myweli.test', '123456');
          upload.complete(ApiResponse.success('https://cdn/a.jpg'));

          expect(await saving, isFalse);
          verifyNever(
            () => auth.updateUser(
              name: any(named: 'name'),
              email: any(named: 'email'),
              avatarUrl: any(named: 'avatarUrl'),
              phone: any(named: 'phone'),
            ),
          );
        },
      );

      test(
        'a profile edit answered after a sign-out does not sign A back in',
        () async {
          final provider = await signedInAs('a');
          final edit = Completer<ApiResponse<User>>();
          when(
            () => auth.updateUser(
              name: any(named: 'name'),
              email: any(named: 'email'),
              avatarUrl: any(named: 'avatarUrl'),
              phone: any(named: 'phone'),
            ),
          ).thenAnswer((_) => edit.future);

          final saving = provider.updateUser(name: 'Awa');
          await pumpEventQueue();
          await provider.logout();
          edit.complete(ApiResponse.success(_user('a')));
          await saving;

          expect(provider.isAuthenticated, isFalse);
          expect(provider.user, isNull);
        },
      );
    });
  });
}
