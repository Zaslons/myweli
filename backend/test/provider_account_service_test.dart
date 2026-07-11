import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/provider_account_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

class _MockProviders extends Mock implements ProvidersRepository {}

class _MockAppointments extends Mock implements AppointmentRepository {}

/// T53 — the storage-erasure half of account deletion: the KYC objects go
/// with the account (own-prefix only; a storage hiccup never blocks).
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryProviderAuthRepository auth;
  late _MockProviders providers;
  late _MockAppointments appointments;

  setUp(() {
    auth = InMemoryProviderAuthRepository(tokens: tokens, isProd: false);
    providers = _MockProviders();
    appointments = _MockAppointments();
    when(
      () => appointments.listForProvider(any()),
    ).thenAnswer((_) async => const []);
    when(
      () => providers.setStatus(any(), any()),
    ).thenAnswer((_) async => {'id': 'p1', 'status': 'draft'});
  });

  Future<String> registerWithKyc({required List<String> keys}) async {
    final reg = await auth.register(
      businessName: 'X',
      businessType: 'salon',
      phoneNumber: '+2250700000070',
      email: 'del@test.pro',
      authProvider: 'google',
      googleSub: 'del-sub',
      providerId: 'p1',
    );
    final id = reg.provider!.id;
    await auth.submitKyc(id, [
      for (final k in keys) {'key': k, 'type': 'id_front'},
    ]);
    return id;
  }

  test('deletes each own-prefix KYC object then the account', () async {
    final deleted = <String>[];
    final service = ProviderAccountService(
      auth,
      providers,
      appointments,
      const FakeStorageService(),
      client: MockClient((req) async {
        expect(req.method, 'DELETE');
        deleted.add(req.url.path);
        return http.Response('', 204);
      }),
    );
    final id = await registerWithKyc(
      keys: ['kyc/PLACEHOLDER/a.jpg', 'kyc/PLACEHOLDER/b.pdf'],
    );
    // Re-submit with the real account id in the prefix.
    await auth.submitKyc(id, [
      {'key': 'kyc/$id/a.jpg', 'type': 'id_front'},
      {'key': 'kyc/$id/b.pdf', 'type': 'id_back'},
      // A foreign / malformed key must be SKIPPED (defense in depth).
      {'key': 'kyc/other-account/c.jpg', 'type': 'selfie'},
    ]);

    final r = await service.deleteAccount(id);
    expect(r.ok, isTrue);
    expect(deleted, hasLength(2));
    expect(deleted[0], contains('kyc/$id/a.jpg'));
    expect(deleted[1], contains('kyc/$id/b.pdf'));
    expect(await auth.accountById(id), isNull);
    verify(() => providers.setStatus('p1', 'draft')).called(1);
  });

  test('a storage failure never blocks the account erasure', () async {
    final service = ProviderAccountService(
      auth,
      providers,
      appointments,
      const FakeStorageService(),
      client: MockClient((req) async => throw Exception('storage down')),
    );
    final id = await registerWithKyc(keys: []);
    await auth.submitKyc(id, [
      {'key': 'kyc/$id/a.jpg', 'type': 'id_front'},
    ]);

    final r = await service.deleteAccount(id);
    expect(r.ok, isTrue);
    expect(await auth.accountById(id), isNull);
  });

  test('future bookings gate fires before any erasure', () async {
    final service = ProviderAccountService(
      auth,
      providers,
      appointments,
      const FakeStorageService(),
      client: MockClient((req) async => fail('no storage call expected')),
    );
    final id = await registerWithKyc(keys: []);
    final future = DateTime.now()
        .toUtc()
        .add(const Duration(days: 2))
        .toIso8601String();
    when(() => appointments.listForProvider('p1')).thenAnswer(
      (_) async => [
        {'status': 'pending', 'appointmentDate': future},
      ],
    );

    final r = await service.deleteAccount(id);
    expect(r.ok, isFalse);
    expect(r.error, 'future_bookings');
    expect(await auth.accountById(id), isNotNull);
    verifyNever(() => providers.setStatus(any(), any()));
  });
}
