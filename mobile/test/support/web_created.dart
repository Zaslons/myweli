import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_ids.dart';

/// What the WEB creates, seeded the way the server writes it.
///
/// The Pro app no longer signs a business up nor adds a salon (App Store
/// 3.1.1 — docs/design/pro-app-login-only.md): `/pro/inscription` and
/// `/pro/salons/nouveau` on myweli.com do. A test that needs a fresh owner
/// or a second salon seeds what the web made, then the app signs in — the
/// real sequence. These mirror the mock's former `registerProviderWith…` and
/// `addSalon`, which mirrored the server: a DRAFT salon, empty and at a 0 %
/// deposit (hygiene-batch9.md §2.5), its owner linked.

/// A salon signed up on the web (`POST /auth/provider/register…`): its draft
/// salon and its owner account. Not signed in — the app does that.
ProviderUser seedWebSignUp({
  required String email,
  String businessName = 'Salon Neuf',
  BusinessType businessType = BusinessType.salon,
  String phoneNumber = '+2250700000009',
  String? address,
}) {
  final salonId = SalonId(MockIds.next('provider_reg'));
  MockData.providers.add(
    MockData.newSalon(
      id: salonId,
      name: businessName,
      businessType: businessType,
      phoneNumber: phoneNumber,
      address: address,
    ),
  );
  final account = ProviderUser(
    id: MockIds.next('provider'),
    phoneNumber: phoneNumber,
    businessName: businessName,
    businessType: businessType,
    email: email.trim().toLowerCase(),
    address: address,
    createdAt: AppClock.now(),
    providerId: salonId,
  );
  MockData.providerUsers.add(account);
  return account;
}

/// A salon added on the web by a live Réseau owner (`POST /me/salons`): a
/// draft in its own free SETUP state, the owner's ACTIVE row in it.
SalonId seedWebAddedSalon(
  ProviderUser owner, {
  String name = 'Salon Neuf',
  BusinessType businessType = BusinessType.salon,
  String phoneNumber = '',
  String? address,
}) {
  final id = SalonId(MockIds.next('provider_add'));
  MockData.providers.add(
    MockData.newSalon(
      id: id,
      name: name,
      businessType: businessType,
      phoneNumber: phoneNumber,
      address: address,
      verified: owner.verificationStatus == VerificationStatus.verified,
    ),
  );
  MockData.draftSalonIds.add(id);
  MockData.teamMembers.add(
    TeamMember(
      id: 'mem_add_$id',
      providerId: id,
      email: owner.email ?? owner.phoneNumber,
      role: TeamRole.owner,
      status: TeamMemberStatus.active,
      invitedAt: AppClock.now(),
      accountId: owner.id,
      acceptedAt: AppClock.now(),
    ),
  );
  return id;
}
