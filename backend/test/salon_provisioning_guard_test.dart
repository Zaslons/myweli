import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';
import 'package:test/test.dart';

/// docs/design/backend-integrity-batch6.md §2.8 (B6.8b) — T72 in depth.
/// The route stopped reading a client-chosen salon (2026-10-14), so nothing
/// can link an account to someone else's salon today; but `ensureSalon`'s
/// already-linked path still wrote an ACTIVE owner row for whatever salon
/// the account pointed at. If anything ever links one again, it refuses: no
/// owner row, a `ensure_salon REFUSED` line.
void main() {
  late InMemoryProvidersRepository providers;
  late InMemoryProviderAuthRepository auth;
  late InMemoryMembershipRepository members;
  late List<String> logs;
  late SalonProvisioningService service;

  setUp(() {
    providers = InMemoryProvidersRepository();
    auth = InMemoryProviderAuthRepository(
      tokens: TokenService(secret: 'test-secret'),
      echoDevCode: true,
    );
    members = InMemoryMembershipRepository();
    logs = [];
    service = SalonProvisioningService(providers, auth, members, log: logs.add);
  });

  Future<ProviderAccount> account(String email, String sub) async {
    final r = await auth.register(
      businessName: 'Salon $sub',
      businessType: 'salon',
      phoneNumber: '+22505000099${sub.length}${sub.codeUnitAt(0) % 10}',
      email: email,
      authProvider: 'google',
      googleSub: sub,
    );
    return r.provider!;
  }

  test('an account linked to a salon ANOTHER account owns gets no owner row '
      'there — refused, said', () async {
    final owner = await service.ensureSalon(await account('a@salon.ci', 'a'));
    final salon = owner.providerId!;

    final intruder = await account('b@salon.ci', 'bb');
    intruder.providerId = salon; // a link nothing should be able to make
    await service.ensureSalon(intruder);

    expect(await members.activeMember(intruder.id, salon), isNull);
    final owners = [
      for (final m in await members.listForProvider(salon))
        if (m.role == 'owner') m.accountId,
    ];
    expect(owners, [owner.id]);
    expect(logs, contains(contains('ensure_salon REFUSED')));
  });

  test('CONTROL — the owner’s own already-linked salon: its row is kept, '
      'nothing refused', () async {
    final owner = await service.ensureSalon(await account('c@salon.ci', 'c'));
    await service.ensureSalon(owner);

    expect(await members.activeMember(owner.id, owner.providerId!), isNotNull);
    expect(logs.where((l) => l.contains('REFUSED')), isEmpty);
  });

  test('CONTROL — a linked salon with NO owner row yet (pre-0027) gets its '
      'owner row', () async {
    final linked = await account('d@salon.ci', 'd');
    final created = await providers.createSalon(
      name: 'Ancien',
      category: 'salon',
      phoneNumber: '',
      address: '',
    );
    linked.providerId = created['id'] as String;
    await service.ensureSalon(linked);

    expect(
      (await members.activeMember(linked.id, linked.providerId!))?.role,
      'owner',
    );
  });
}
