/// Module `access` §2 (docs/modules/access.md): the capability list and the
/// FOUR preset roles, in one file. Routes/services check CAPABILITIES, never
/// role names — presets are just seed sets.
library;

/// The unit of enforcement (§2.1). New modules append here.
abstract final class Cap {
  /// See the whole salon's bookings/calendar.
  static const journalViewAll = 'journal.view.all';

  /// Accept/reject/cancel/complete/no-show/reschedule/manual-book any booking.
  static const journalManageAll = 'journal.manage.all';

  /// See own (linked artist's) bookings only.
  static const journalViewOwn = 'journal.view.own';

  /// Complete / no-show own bookings.
  static const journalManageOwn = 'journal.manage.own';

  /// The salon client base (`clients` module) — every read audited.
  static const clientsView = 'clients.view';

  /// Services, artist records, media (gallery/before-after).
  static const catalogueManage = 'catalogue.manage';

  /// Salon hours, breaks, buffers.
  static const availabilityManage = 'availability.manage';

  /// Salon public profile (PATCH /providers/{id} allowlist).
  static const profileManage = 'profile.manage';

  /// Revenue figures (earnings, dashboard revenue fields).
  static const financesView = 'finances.view';

  /// Deposit policy settings (percentage, MoMo number).
  static const depositManage = 'deposit.manage';

  /// Invite / revoke / change roles.
  static const membersManage = 'members.manage';

  /// Plan & billing.
  static const subscriptionManage = 'subscription.manage';

  /// Take the salon live / unpublish it (sign-off 2026-07-11: owner-only —
  /// going live is an existential business act, like deposits and billing).
  static const salonPublish = 'salon.publish';
}

/// Preset roles (§2.2, sign-off 2026-07-11: Réception ships now).
abstract final class MemberRole {
  static const owner = 'owner';
  static const manager = 'manager';
  static const reception = 'reception';
  static const staff = 'staff'; // Collaborateur

  static const all = {owner, manager, reception, staff};
}

const Set<String> _ownCaps = {Cap.journalViewOwn, Cap.journalManageOwn};

const Set<String> _managerCaps = {
  Cap.journalViewAll,
  Cap.journalManageAll,
  ..._ownCaps,
  Cap.clientsView,
  Cap.catalogueManage,
  Cap.availabilityManage,
  Cap.profileManage,
};

/// `role → capabilities` — the §2.2 matrix, exactly. Effective capabilities
/// for a member = the preset (V3 adds sparse grants/denies on top).
const Map<String, Set<String>> rolePresets = {
  MemberRole.owner: {
    ..._managerCaps,
    Cap.financesView,
    Cap.depositManage,
    Cap.membersManage,
    Cap.subscriptionManage,
    Cap.salonPublish,
  },
  MemberRole.manager: _managerCaps,
  // The front desk: the whole journal + the client base, nothing else.
  MemberRole.reception: {
    Cap.journalViewAll,
    Cap.journalManageAll,
    ..._ownCaps,
    Cap.clientsView,
  },
  // Collaborateur: « ma journée » only.
  MemberRole.staff: _ownCaps,
};

/// Deny-by-default preset lookup (unknown role → no capabilities).
Set<String> capabilitiesFor(String role) => rolePresets[role] ?? const {};
