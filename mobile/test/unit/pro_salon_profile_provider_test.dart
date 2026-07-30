import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/providers/pro_salon_profile_provider.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';

class _MockProService extends Mock implements ProServiceInterface {}

class _MockProviderService extends Mock implements ProviderServiceInterface {}

/// Salon profile editing in the pro app (pro-salon-lifecycle L2):
/// load / save / error paths.
void main() {
  late _MockProService pro;
  late _MockProviderService providers;

  final salon = Provider.fromJson({
    'id': 'p1',
    'name': 'Salon Awa',
    'description': 'Desc',
    'address': 'Rue des Jardins',
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
  });

  setUpAll(() {
    pro = _MockProService();
    providers = _MockProviderService();
    serviceLocator.proService = pro;
    serviceLocator.providerService = providers;
  });

  setUp(() {
    reset(pro);
    reset(providers);
  });

  test('load populates the listing; failure surfaces the error', () async {
    when(() => providers.getProviderById('p1'))
        .thenAnswer((_) async => ApiResponse.success(salon));
    final p = ProSalonProfileProvider();
    await p.load('p1');
    expect(p.provider?.name, 'Salon Awa');

    when(() => providers.getProviderById('p1'))
        .thenAnswer((_) async => ApiResponse.error('boom'));
    await p.load('p1');
    expect(p.provider, isNull);
    expect(p.error, 'boom');
  });

  test('save sends the changes and refreshes the listing', () async {
    final updated = salon.copyWith(latitude: 5.36, longitude: -3.99);
    when(() => pro.updateSalonProfile('p1', any()))
        .thenAnswer((_) async => ApiResponse.success(updated));

    final p = ProSalonProfileProvider();
    final ok = await p.save('p1', {'latitude': 5.36, 'longitude': -3.99});
    expect(ok, isTrue);
    expect(p.provider?.latitude, 5.36);
    expect(p.isSaving, isFalse);
    verify(() => pro.updateSalonProfile('p1', {
          'latitude': 5.36,
          'longitude': -3.99,
        })).called(1);
  });

  test('a rejected save keeps the error visible', () async {
    when(() => pro.updateSalonProfile('p1', any()))
        .thenAnswer((_) async => ApiResponse.error('Numéro invalide'));
    final p = ProSalonProfileProvider();
    expect(await p.save('p1', {'phoneNumber': 'abc'}), isFalse);
    expect(p.error, 'Numéro invalide');
  });
}
