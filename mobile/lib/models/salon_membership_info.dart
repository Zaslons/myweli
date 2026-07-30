import 'package:equatable/equatable.dart';

import 'team_member.dart';

/// One « Mes salons » entry (module `access` R6 — GET /me/salons): a salon
/// the account holds an ACTIVE membership in, with the caller's role there
/// and enough salon surface for the switcher (name, status, badge, thumb).
class SalonMembershipInfo extends Equatable {
  const SalonMembershipInfo({
    required this.salonId,
    required this.salonName,
    required this.role,
    required this.salonStatus,
    required this.verified,
    this.imageUrl,
  });

  final String salonId;
  final String salonName;
  final TeamRole role;

  /// `draft` (setup/unpublished) · `active` (live) · `suspended`.
  final String salonStatus;
  final bool verified;
  final String? imageUrl;

  bool get isOwner => role == TeamRole.owner;
  bool get isDraft => salonStatus == 'draft';

  factory SalonMembershipInfo.fromJson(Map<String, dynamic> json) =>
      SalonMembershipInfo(
        salonId: json['salonId'] as String,
        salonName: (json['salonName'] as String?) ?? '',
        role: teamRoleFrom(json['role'] as String?),
        salonStatus: (json['salonStatus'] as String?) ?? 'active',
        verified: json['verified'] == true,
        imageUrl: json['imageUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'salonId': salonId,
        'salonName': salonName,
        'role': role.name,
        'salonStatus': salonStatus,
        'verified': verified,
        if (imageUrl != null) 'imageUrl': imageUrl,
      };

  @override
  List<Object?> get props =>
      [salonId, salonName, role, salonStatus, verified, imageUrl];
}

/// The GET /me/salons payload: the picker list + the SERVER-computed
/// « Ajouter un salon » gate (clients never derive rights).
class MySalonsResult extends Equatable {
  const MySalonsResult({required this.items, required this.canAddSalon});

  final List<SalonMembershipInfo> items;
  final bool canAddSalon;

  factory MySalonsResult.fromJson(Map<String, dynamic> json) => MySalonsResult(
        items: ((json['items'] as List?) ?? const [])
            .map((e) => SalonMembershipInfo.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        canAddSalon: json['canAddSalon'] == true,
      );

  @override
  List<Object?> get props => [items, canAddSalon];
}
