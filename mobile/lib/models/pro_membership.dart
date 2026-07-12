import 'package:equatable/equatable.dart';

import 'team_member.dart';

/// App-side capability names — MIRROR of the backend's
/// `lib/src/access/capabilities.dart` (module `access`). UI gating is
/// convenience only; the server recomputes every decision.
abstract final class ProCap {
  static const journalViewAll = 'journal.view.all';
  static const journalManageAll = 'journal.manage.all';
  static const journalViewOwn = 'journal.view.own';
  static const journalManageOwn = 'journal.manage.own';
  static const clientsView = 'clients.view';
  static const catalogueManage = 'catalogue.manage';
  static const availabilityManage = 'availability.manage';
  static const profileManage = 'profile.manage';
  static const financesView = 'finances.view';
  static const depositManage = 'deposit.manage';
  static const membersManage = 'members.manage';
  static const subscriptionManage = 'subscription.manage';
  static const salonPublish = 'salon.publish';
}

const Set<String> _ownCaps = {ProCap.journalViewOwn, ProCap.journalManageOwn};

const Set<String> _managerCaps = {
  ProCap.journalViewAll,
  ProCap.journalManageAll,
  ..._ownCaps,
  ProCap.clientsView,
  ProCap.catalogueManage,
  ProCap.availabilityManage,
  ProCap.profileManage,
};

/// The §2.2 preset matrix — used ONLY by the MOCK backend (the API always
/// ships server-computed capabilities; clients never derive rights).
Set<String> presetCapabilitiesFor(TeamRole role) => switch (role) {
      TeamRole.owner => {
          ..._managerCaps,
          ProCap.financesView,
          ProCap.depositManage,
          ProCap.membersManage,
          ProCap.subscriptionManage,
          ProCap.salonPublish,
        },
      TeamRole.manager => _managerCaps,
      TeamRole.reception => {
          ProCap.journalViewAll,
          ProCap.journalManageAll,
          ..._ownCaps,
          ProCap.clientsView,
        },
      TeamRole.staff => _ownCaps,
    };

/// The signed-in identity's membership in its acting salon — mirrors the
/// `membership` block of GET /me/provider (team access R4a), with the salon
/// id/name folded in by the service so ONE persisted blob shapes the app
/// offline. Design: docs/design/team-access-r4-role-shaped-app.md.
class ProMembership extends Equatable {
  const ProMembership({
    required this.role,
    required this.capabilities,
    required this.salonId,
    required this.salonName,
    this.artistId,
    this.artistName,
  });

  final TeamRole role;

  /// SERVER-computed capability names (sorted by the backend).
  final Set<String> capabilities;

  /// The Collaborateur's linked employee record.
  final String? artistId;
  final String? artistName;

  final String salonId;
  final String salonName;

  bool can(String capability) => capabilities.contains(capability);
  bool get isStaff => role == TeamRole.staff;
  String get roleLabel => teamRoleLabel(role);

  factory ProMembership.fromJson(Map<String, dynamic> json) => ProMembership(
        role: TeamRole.values.firstWhere(
          (e) => e.name == json['role'],
          orElse: () => TeamRole.staff, // safe minimal fallback
        ),
        capabilities: ((json['capabilities'] as List?) ?? const [])
            .cast<String>()
            .toSet(),
        artistId: json['artistId'] as String?,
        artistName: json['artistName'] as String?,
        salonId: json['salonId'] as String? ?? '',
        salonName: json['salonName'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'capabilities': capabilities.toList()..sort(),
        'artistId': artistId,
        'artistName': artistName,
        'salonId': salonId,
        'salonName': salonName,
      };

  @override
  List<Object?> get props =>
      [role, capabilities, artistId, artistName, salonId, salonName];
}
