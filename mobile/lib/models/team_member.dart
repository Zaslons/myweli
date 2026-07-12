import 'package:equatable/equatable.dart';

/// The four preset roles (module `access` §2.2). Enforcement is server-side
/// (capabilities); the app only labels and shapes.
enum TeamRole { owner, manager, reception, staff }

enum TeamMemberStatus { active, invited, revoked }

/// French display label for a role.
String teamRoleLabel(TeamRole role) => switch (role) {
      TeamRole.owner => 'Propriétaire',
      TeamRole.manager => 'Manager',
      TeamRole.reception => 'Réception',
      TeamRole.staff => 'Collaborateur',
    };

/// A salon team row — the owner, an active member, or a pending invitation.
/// Mirrors the backend `TeamMember` DTO (team access R2b).
/// Design: docs/design/team-access-r3-app.md.
class TeamMember extends Equatable {
  const TeamMember({
    required this.id,
    required this.providerId,
    required this.email,
    required this.role,
    required this.status,
    required this.invitedAt,
    this.accountId,
    this.artistId,
    this.artistName,
    this.acceptedAt,
    this.revokedAt,
    this.expiresAt,
    this.resendsLeft = 0,
    this.expired = false,
  });

  final String id;
  final String providerId;
  final String email;
  final TeamRole role;
  final TeamMemberStatus status;
  final DateTime invitedAt;
  final String? accountId;

  /// The linked employee record (REQUIRED for Collaborateur).
  final String? artistId;
  final String? artistName;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;

  /// Invitation validity (7 days from invite/resend); null on active rows.
  final DateTime? expiresAt;

  /// Remaining « Renvoyer l'invitation » budget.
  final int resendsLeft;

  /// True when an invited row is past its expiry (server-derived).
  final bool expired;

  bool get isPending => status == TeamMemberStatus.invited;
  bool get isOwner => role == TeamRole.owner;
  String get roleLabel => teamRoleLabel(role);

  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
        id: json['id'] as String,
        providerId: json['providerId'] as String? ?? '',
        email: json['email'] as String? ?? '',
        role: TeamRole.values.firstWhere(
          (e) => e.name == json['role'],
          orElse: () => TeamRole.staff,
        ),
        status: TeamMemberStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => TeamMemberStatus.revoked,
        ),
        invitedAt: DateTime.tryParse(json['invitedAt'] as String? ?? '') ??
            DateTime.now(),
        accountId: json['accountId'] as String?,
        artistId: json['artistId'] as String?,
        artistName: json['artistName'] as String?,
        acceptedAt: json['acceptedAt'] == null
            ? null
            : DateTime.tryParse(json['acceptedAt'] as String),
        revokedAt: json['revokedAt'] == null
            ? null
            : DateTime.tryParse(json['revokedAt'] as String),
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.tryParse(json['expiresAt'] as String),
        resendsLeft: (json['resendsLeft'] as num?)?.toInt() ?? 0,
        expired: json['expired'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'providerId': providerId,
        'email': email,
        'role': role.name,
        'status': status.name,
        'invitedAt': invitedAt.toIso8601String(),
        'accountId': accountId,
        'artistId': artistId,
        'artistName': artistName,
        'acceptedAt': acceptedAt?.toIso8601String(),
        'revokedAt': revokedAt?.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'resendsLeft': resendsLeft,
        'expired': expired,
      };

  TeamMember copyWith({
    TeamRole? role,
    TeamMemberStatus? status,
    String? accountId,
    String? artistId,
    String? artistName,
    DateTime? acceptedAt,
    DateTime? revokedAt,
    DateTime? expiresAt,
    int? resendsLeft,
    bool? expired,
  }) =>
      TeamMember(
        id: id,
        providerId: providerId,
        email: email,
        role: role ?? this.role,
        status: status ?? this.status,
        invitedAt: invitedAt,
        accountId: accountId ?? this.accountId,
        artistId: artistId ?? this.artistId,
        artistName: artistName ?? this.artistName,
        acceptedAt: acceptedAt ?? this.acceptedAt,
        revokedAt: revokedAt ?? this.revokedAt,
        expiresAt: expiresAt ?? this.expiresAt,
        resendsLeft: resendsLeft ?? this.resendsLeft,
        expired: expired ?? this.expired,
      );

  @override
  List<Object?> get props => [
        id,
        providerId,
        email,
        role,
        status,
        invitedAt,
        accountId,
        artistId,
        artistName,
        acceptedAt,
        revokedAt,
        expiresAt,
        resendsLeft,
        expired,
      ];
}
