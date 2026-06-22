import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/services/interfaces/auth_service_interface.dart';
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
      serviceLocator.imageUploadService = MockImageUploadService();
    });

    setUp(() {
      reset(auth);
      when(() => auth.getCurrentUser()).thenAnswer((_) async => baseUser);
      when(() => auth.updateUser(
            name: any(named: 'name'),
            email: any(named: 'email'),
            avatarUrl: any(named: 'avatarUrl'),
          )).thenAnswer((inv) async => ApiResponse.success(
            baseUser.copyWith(
                avatarUrl: inv.namedArguments[#avatarUrl] as String?),
          ));
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
  });
}
