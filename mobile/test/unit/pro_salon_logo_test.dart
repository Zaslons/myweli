import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/providers/pro_salon_profile_provider.dart';
import 'package:myweli/services/interfaces/image_upload_service_interface.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';

class _MockProService extends Mock implements ProServiceInterface {}

/// The pro-gallery slot rigged to fail loudly — the consumer-avatar test's
/// pattern (consumer_avatar_test.dart): under `flutter test` every slot is a
/// MockImageUploadService, so `isA<>` proves nothing; instance identity is
/// the only assertion that can tell the logo slot from the gallery one.
class _ForbiddenUploadService implements ImageUploadServiceInterface {
  @override
  Future<ApiResponse<String>> uploadImage({
    required String source,
    void Function(double progress)? onProgress,
  }) async => ApiResponse.error(
    'WRONG SLOT: the logo upload reached the pro GALLERY instance — '
    'purpose=gallery files the mark under gallery/{providerId}/, where every '
    'future gallery sweep treats it as a portfolio photo (salon-logo.md §5).',
  );
}

Provider _salon({String? logoUrl}) => Provider.fromJson({
  'id': 'p1',
  'name': 'Salon X',
  'description': 'Desc',
  'address': 'a',
  'commune': 'Cocody',
  'city': 'Abidjan',
  'imageUrls': <String>[],
  'rating': 0,
  'reviewCount': 0,
  'services': <Map<String, dynamic>>[],
  'artists': <Map<String, dynamic>>[],
  'availability': {
    'providerId': 'p1',
    'weeklySchedule': <String, dynamic>{},
    'blockedDates': <String>[],
    'bufferMinutes': 0,
  },
  'phoneNumber': '+2250700000001',
  'category': 'salon',
  'logoUrl': ?logoUrl,
});

void main() {
  late _MockProService pro;

  setUpAll(() {
    pro = _MockProService();
    serviceLocator.proService = pro;
    serviceLocator.logoImageUploadService = MockImageUploadService();
    serviceLocator.imageUploadService = _ForbiddenUploadService();
  });

  setUp(() => reset(pro));

  test(
    'uploadLogo uses the LOGO slot, uploads, then PATCHes only logoUrl',
    () async {
      const source = 'asset:assets/images/providers/spa_relax_photo.png';
      when(
        () => pro.updateSalonProfile('p1', {'logoUrl': source}),
      ).thenAnswer((_) async => ApiResponse.success(_salon(logoUrl: source)));

      final p = ProSalonProfileProvider();
      final ok = await p.uploadLogo('p1', source);

      expect(ok, isTrue, reason: p.logoError ?? '');
      expect(p.provider?.logoUrl, source);
      expect(p.isUploadingLogo, isFalse);
      verify(() => pro.updateSalonProfile('p1', {'logoUrl': source})).called(1);
    },
  );

  test("removeLogo sends the empty string — the contract's delete", () async {
    when(
      () => pro.updateSalonProfile('p1', {'logoUrl': ''}),
    ).thenAnswer((_) async => ApiResponse.success(_salon()));
    final p = ProSalonProfileProvider();
    expect(await p.removeLogo('p1'), isTrue);
    verify(() => pro.updateSalonProfile('p1', {'logoUrl': ''})).called(1);
  });

  test('a failed upload surfaces the inline error and saves nothing', () async {
    // The DI slots are `late final` — assigned once, ever — so the failure
    // is provoked through the mock's own contract (an empty source is
    // « Image invalide ») rather than by swapping the slot.
    final p = ProSalonProfileProvider();
    expect(await p.uploadLogo('p1', ''), isFalse);
    expect(p.logoError, isNotNull);
    verifyNever(() => pro.updateSalonProfile(any(), any()));
  });
}
