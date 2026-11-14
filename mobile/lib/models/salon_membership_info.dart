import 'package:equatable/equatable.dart';

import '../core/utils/salon_id.dart';

import 'salon_validation.dart';
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
    this.validation,
    this.validationSent = false,
  }) : assert(
         validation == null || validationSent,
         'a validation is always a sent key',
       );

  final SalonId salonId;
  final String salonName;
  final TeamRole role;

  /// `draft` (setup/unpublished) · `active` (live) · `suspended`.
  final String salonStatus;
  final bool verified;
  final String? imageUrl;

  /// Where the salon stands with MyWeli's validation (B0.18 —
  /// docs/design/salon-go-live-approval.md §3.5): null while it never asked,
  /// or when the server sent no key ([validationSent] false). A member who
  /// is not the owner reads it without `offerLive` and without the note.
  final SalonValidation? validation;

  /// The server sent the `validation` key (a B0.18 server). False on a server
  /// from before B0.18 — the row then keeps today's words (decision 136 item
  /// 10; [readSalonValidationKey]).
  final bool validationSent;

  bool get isOwner => role == TeamRole.owner;
  bool get isDraft => salonStatus == 'draft';

  factory SalonMembershipInfo.fromJson(Map<String, dynamic> json) {
    final v = readSalonValidationKey(json);
    return SalonMembershipInfo(
      salonId: SalonId(json['salonId'] as String),
      salonName: (json['salonName'] as String?) ?? '',
      role: teamRoleFrom(json['role'] as String?),
      salonStatus: (json['salonStatus'] as String?) ?? 'active',
      verified: json['verified'] == true,
      imageUrl: json['imageUrl'] as String?,
      validation: v.validation,
      validationSent: v.sent,
    );
  }

  /// The wire shape back: the `validation` key only when the server sent one
  /// (`null` included), so « never asked » and « a server before B0.18 »
  /// survive a round trip as two different answers.
  Map<String, dynamic> toJson() => {
    'salonId': salonId,
    'salonName': salonName,
    'role': role.name,
    'salonStatus': salonStatus,
    'verified': verified,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (validationSent) 'validation': validation?.toJson(),
  };

  @override
  List<Object?> get props => [
    salonId,
    salonName,
    role,
    salonStatus,
    verified,
    imageUrl,
    validation,
    validationSent,
  ];
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
