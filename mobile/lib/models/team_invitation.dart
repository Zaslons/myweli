import 'package:equatable/equatable.dart';

import 'team_member.dart';

/// A pending-invitation card as shown to the INVITEE — mirrors the backend
/// `TeamInvitation` DTO (team access R2b: the 202 login bridge and
/// GET /me/provider/invitations). No salon internals beyond the name.
class TeamInvitation extends Equatable {
  const TeamInvitation({
    required this.id,
    required this.providerId,
    required this.salonName,
    required this.role,
    required this.roleLabel,
    required this.expiresAt,
  });

  final String id;
  final String providerId;
  final String salonName;
  final TeamRole role;

  /// Server-provided French label (Manager / Réception / Collaborateur).
  final String roleLabel;
  final DateTime? expiresAt;

  factory TeamInvitation.fromJson(Map<String, dynamic> json) {
    final role = TeamRole.values.firstWhere(
      (e) => e.name == json['role'],
      orElse: () => TeamRole.staff,
    );
    return TeamInvitation(
      id: json['id'] as String,
      providerId: json['providerId'] as String? ?? '',
      salonName: json['salonName'] as String? ?? 'Salon',
      role: role,
      roleLabel: json['roleLabel'] as String? ?? teamRoleLabel(role),
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.tryParse(json['expiresAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'providerId': providerId,
        'salonName': salonName,
        'role': role.name,
        'roleLabel': roleLabel,
        'expiresAt': expiresAt?.toIso8601String(),
      };

  @override
  List<Object?> get props =>
      [id, providerId, salonName, role, roleLabel, expiresAt];
}
