import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/services/interfaces/auth_service_interface.dart';
import 'package:myweli/services/interfaces/image_upload_service_interface.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';

class _MockAuthService extends Mock implements AuthServiceInterface {}

void main() {
  test('User round-trips avatarUrl through JSON (+ null default)', () {
    final user = User(
      id: 'u1',
      phoneNumber: '+2250700000000',
      name: 'Ama',
      avatarUrl: 'asset:assets/images/providers/spa_relax_photo.png',
      createdAt: DateTime(2026),
    );
    final back = User.fromJson(user.toJson());
    expect(back, user);
    expect(back.avatarUrl, user.avatarUrl);

    final json = user.toJson()..remove('avatarUrl');
    expect(User.fromJson(json).avatarUrl, isNull);
  });

  group('AuthProvider.uploadAvatar', () {
    late _MockAuthService auth;

    final baseUser = User(
      id: 'u1',
      phoneNumber: '+2250700000000',
      name: 'Ama',
      createdAt: DateTime(2026),
    );

    setUpAll(() {
      auth = _MockAuthService();
      serviceLocator.authService = auth;
      // **This line is why the defect survived.** It registered the slot the
      // buggy code happened to read — the PRO gallery instance — so the test
      // went green against wiring that could never work in API mode. The
      // consumer avatar has its own slot now, and the gallery one is a fake
      // that FAILS the test if anything reaches for it (see below).
      serviceLocator.avatarImageUploadService = MockImageUploadService();
      serviceLocator.imageUploadService = _ForbiddenUploadService();
    });

    setUp(() {
      reset(auth);
      when(() => auth.getCurrentUser()).thenAnswer((_) async => baseUser);
      when(
        () => auth.updateUser(
          name: any(named: 'name'),
          email: any(named: 'email'),
          avatarUrl: any(named: 'avatarUrl'),
        ),
      ).thenAnswer(
        (inv) async => ApiResponse.success(
          baseUser.copyWith(
            avatarUrl: inv.namedArguments[#avatarUrl] as String?,
          ),
        ),
      );
    });

    test('uploads then saves the URL on the user', () async {
      final provider = AuthProvider();
      const source = 'asset:assets/images/providers/spa_relax_photo.png';

      final ok = await provider.uploadAvatar(source);

      expect(ok, isTrue);
      expect(provider.user?.avatarUrl, source);
      expect(provider.isUploadingAvatar, isFalse);
      verify(() => auth.updateUser(avatarUrl: source)).called(1);
    });

    test('it uses the AVATAR slot, never the pro gallery one', () async {
      // The wiring pin. `isA<>` cannot express this — under `flutter test`
      // every slot is a MockImageUploadService, because AppConfig.useApiBackend
      // is a compile-time false and DI never builds an Api* instance. So the
      // assertion is instance identity: the gallery slot throws, and reaching
      // it is what fails the test.
      //
      // Against the old wiring (`serviceLocator.imageUploadService`) this test
      // fails with the fake's own message, naming the bug.
      final provider = AuthProvider();
      await expectLater(
        provider.uploadAvatar('asset:x.png'),
        completion(isTrue),
      );
    });
  });
}

/// The pro-gallery slot, rigged to fail loudly.
///
/// In API mode this instance carries the PRO session store and
/// `purpose: 'gallery'`, which the server role-gates to a provider token — so a
/// consumer reaching it can only ever produce « Non connecté » or a 403. A test
/// that tolerates it proves nothing, so this one refuses.
class _ForbiddenUploadService implements ImageUploadServiceInterface {
  @override
  Future<ApiResponse<String>> uploadImage({
    required String source,
    void Function(double progress)? onProgress,
  }) async => throw StateError(
    'The consumer avatar upload reached the PRO gallery upload service. That '
    'instance holds the provider session and purpose=gallery: in API mode it '
    'returns "Non connecté" on a consumer device, and a 403 if it ever got a '
    'token. Use serviceLocator.avatarImageUploadService.',
  );
}
