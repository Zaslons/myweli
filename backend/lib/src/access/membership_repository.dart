/// Module `access` §3: the membership rows — who can act inside which salon,
/// as which role. One row per (salon, email); `account_id` stays NULL while
/// the invitation is pending (R2). Design: docs/modules/access.md.
library;

class Member {
  Member({
    required this.id,
    required this.providerId,
    required this.email,
    required this.role,
    required this.status,
    required this.invitedAt,
    this.accountId,
    this.artistId,
    this.invitedBy,
    this.acceptedAt,
    this.revokedAt,
    this.expiresAt,
    this.resendsLeft = 3,
  });

  final String id;
  final String providerId;

  /// NULL while invited (the invitation key is [email]).
  final String? accountId;

  /// Lowercased — the invitation key.
  final String email;

  /// `owner` | `manager` | `reception` | `staff` (see MemberRole).
  final String role;

  /// REQUIRED when [role] == staff (the Collaborateur ↔ artist link).
  final String? artistId;

  /// `invited` | `active` | `revoked`.
  final String status;

  final String? invitedBy;
  final DateTime invitedAt;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;

  /// Invitation validity (7 days from invite/resend); null on non-invited
  /// rows (owners, backfill).
  final DateTime? expiresAt;

  /// Invitation resend budget (the email-OTP model).
  final int resendsLeft;

  bool get isExpiredInvitation =>
      status == 'invited' &&
      expiresAt != null &&
      DateTime.now().toUtc().isAfter(expiresAt!);

  Map<String, dynamic> toJson() => {
    'id': id,
    'providerId': providerId,
    'accountId': accountId,
    'email': email,
    'role': role,
    'artistId': artistId,
    'status': status,
    'invitedAt': invitedAt.toIso8601String(),
    'acceptedAt': acceptedAt?.toIso8601String(),
    'revokedAt': revokedAt?.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'resendsLeft': resendsLeft,
  };

  Member copyWith({
    String? accountId,
    String? role,
    String? artistId,
    String? status,
    DateTime? acceptedAt,
    DateTime? revokedAt,
    DateTime? expiresAt,
    int? resendsLeft,
  }) => Member(
    id: id,
    providerId: providerId,
    accountId: accountId ?? this.accountId,
    email: email,
    role: role ?? this.role,
    artistId: artistId ?? this.artistId,
    status: status ?? this.status,
    invitedBy: invitedBy,
    invitedAt: invitedAt,
    acceptedAt: acceptedAt ?? this.acceptedAt,
    revokedAt: revokedAt ?? this.revokedAt,
    expiresAt: expiresAt ?? this.expiresAt,
    resendsLeft: resendsLeft ?? this.resendsLeft,
  );
}

abstract interface class MembershipRepository {
  /// The ACTIVE membership of [accountId] inside [providerId], or null.
  Future<Member?> activeMember(String accountId, String providerId);

  /// The account's first active membership (single-salon assumption at R1;
  /// R6 adds explicit salon selection) — how a member resolves "their" salon.
  Future<Member?> firstActiveForAccount(String accountId);

  /// Every membership row of the account (any status).
  Future<List<Member>> listForAccount(String accountId);

  /// The salon's member rows, owner first (any status; R2 lists pending too).
  Future<List<Member>> listForProvider(String providerId);

  /// Idempotently ensure the salon's OWNER row for [accountId]/[email]
  /// (registration + provisioning self-heal + the 0027 backfill's runtime
  /// mirror).
  Future<Member> ensureOwner({
    required String providerId,
    required String accountId,
    required String email,
  });

  /// Delete every membership row of the account — the identity is being
  /// erased (T53) and a member row never outlives its account. Deleted, not
  /// revoked: a revoked row keeps `account_id`, which references the identity
  /// (docs/design/backend-provider-deletion-member-fk.md). The schema says the
  /// same since 0038 (ON DELETE CASCADE); this keeps the in-memory twin, which
  /// has no foreign keys, telling the same story.
  Future<void> deleteAllForAccount(String accountId);

  // ---- Invitations (R2b — docs/design/team-access-r2b-invitations.md) ----

  /// Create a pending invitation (`status='invited'`, 7-day validity) — or
  /// invite the address again ON ITS DEAD ROW: one row per (salon, email) is
  /// a database fact (`UNIQUE (provider_id, email)`). A row is dead when it
  /// is revoked, or an invitation past its window — never the owner's. The
  /// revived row keeps its id and [Member.accountId] (until [activate]
  /// rewrites it); role, artist, inviter, window and the resend budget start
  /// over.
  ///
  /// Null when a LIVE row holds the address. The service checks first, so
  /// null means a concurrent invitation won the race.
  /// docs/design/backend-team-reinvite.md
  Future<Member?> invite({
    required String providerId,
    required String email,
    required String role,
    required DateTime expiresAt,
    String? artistId,
    String? invitedBy,
  });

  Future<Member?> byId(String memberId);

  /// Pending, UNEXPIRED invitations for a (lowercased) email — the login
  /// bridge's query.
  Future<List<Member>> pendingByEmail(String email);

  /// Role/artist change (the owner row is guarded in the service layer).
  Future<Member?> updateMember(
    String memberId, {
    String? role,
    String? artistId,
  });

  /// Idempotent revoke (invited or active → revoked).
  Future<Member?> revoke(String memberId);

  /// Reset the validity window and consume one resend; null when the budget
  /// is exhausted.
  Future<Member?> resendInvite(String memberId, DateTime newExpiresAt);

  /// Invitation accepted: link the account, flip to active — ONLY if the row
  /// is still a valid invitation (`invited`, window open). Null otherwise: a
  /// revocation, or the window closing, that lands between the caller's read
  /// and this write must hold rather than be overwritten.
  /// docs/design/backend-team-invite-caps.md §5.3
  Future<Member?> activate(String memberId, String accountId);

  /// Invitation declined: the row disappears (the owner can re-invite) —
  /// unless it once belonged to an account (a former member's row, invited
  /// again: [Member.accountId] is set). That one goes back to `revoked`:
  /// deleting it would leave the account with no row at all, and
  /// GET /me/provider would then create a salon for it.
  /// docs/design/backend-team-reinvite.md
  Future<void> decline(String memberId);
}

class InMemoryMembershipRepository implements MembershipRepository {
  final List<Member> _rows = [];
  int _seq = 0;

  @override
  Future<Member?> activeMember(String accountId, String providerId) async {
    for (final m in _rows) {
      if (m.accountId == accountId &&
          m.providerId == providerId &&
          m.status == 'active') {
        return m;
      }
    }
    return null;
  }

  @override
  Future<Member?> firstActiveForAccount(String accountId) async {
    for (final m in _rows) {
      if (m.accountId == accountId && m.status == 'active') return m;
    }
    return null;
  }

  @override
  Future<List<Member>> listForAccount(String accountId) async => [
    for (final m in _rows)
      if (m.accountId == accountId) m,
  ];

  @override
  Future<List<Member>> listForProvider(String providerId) async {
    final rows = [
      for (final m in _rows)
        if (m.providerId == providerId) m,
    ];
    rows.sort((a, b) {
      if (a.role == MemberRoleNames.owner && b.role != MemberRoleNames.owner) {
        return -1;
      }
      if (b.role == MemberRoleNames.owner && a.role != MemberRoleNames.owner) {
        return 1;
      }
      return a.invitedAt.compareTo(b.invitedAt);
    });
    return rows;
  }

  @override
  Future<Member> ensureOwner({
    required String providerId,
    required String accountId,
    required String email,
  }) async {
    final existing = await activeMember(accountId, providerId);
    if (existing != null && existing.role == MemberRoleNames.owner) {
      return existing;
    }
    final now = DateTime.now().toUtc();
    final member = Member(
      id: 'mem_${++_seq}',
      providerId: providerId,
      accountId: accountId,
      email: email.toLowerCase(),
      role: MemberRoleNames.owner,
      status: 'active',
      invitedAt: now,
      acceptedAt: now,
    );
    _rows.add(member);
    return member;
  }

  @override
  Future<void> deleteAllForAccount(String accountId) async {
    _rows.removeWhere((m) => m.accountId == accountId);
  }

  @override
  Future<Member?> invite({
    required String providerId,
    required String email,
    required String role,
    required DateTime expiresAt,
    String? artistId,
    String? invitedBy,
  }) async {
    final key = email.toLowerCase();
    final now = DateTime.now().toUtc();
    // The twin of Postgres's UNIQUE (provider_id, email) + ON CONFLICT — the
    // rule this twin lacked, which let every test pass on a second row.
    final at = _rows.indexWhere(
      (m) => m.providerId == providerId && m.email == key,
    );
    if (at >= 0) {
      final old = _rows[at];
      if (!_isDead(old, now)) return null;
      // Rebuilt rather than copyWith'd: copyWith cannot clear a field, and
      // acceptedAt, revokedAt and a staff artistId must go.
      return _rows[at] = Member(
        id: old.id,
        providerId: providerId,
        accountId: old.accountId,
        email: key,
        role: role,
        artistId: artistId,
        status: 'invited',
        invitedBy: invitedBy,
        invitedAt: now,
        expiresAt: expiresAt,
      );
    }
    final member = Member(
      id: 'mem_${++_seq}',
      providerId: providerId,
      email: key,
      role: role,
      artistId: artistId,
      status: 'invited',
      invitedBy: invitedBy,
      invitedAt: now,
      expiresAt: expiresAt,
    );
    _rows.add(member);
    return member;
  }

  /// The Postgres `WHERE` of the revival, word for word: revoked, or an
  /// invitation whose window has closed (`expires_at <= now()`) — and never
  /// the owner's row.
  static bool _isDead(Member m, DateTime now) =>
      m.role != MemberRoleNames.owner &&
      (m.status == 'revoked' ||
          (m.status == 'invited' &&
              m.expiresAt != null &&
              !m.expiresAt!.isAfter(now)));

  @override
  Future<Member?> byId(String memberId) async {
    for (final m in _rows) {
      if (m.id == memberId) return m;
    }
    return null;
  }

  @override
  Future<List<Member>> pendingByEmail(String email) async {
    final key = email.toLowerCase();
    final now = DateTime.now().toUtc();
    return [
      for (final m in _rows)
        if (m.email == key &&
            m.status == 'invited' &&
            (m.expiresAt == null || now.isBefore(m.expiresAt!)))
          m,
    ];
  }

  Future<Member?> _mutate(String memberId, Member Function(Member) fn) async {
    for (var i = 0; i < _rows.length; i++) {
      if (_rows[i].id == memberId) {
        _rows[i] = fn(_rows[i]);
        return _rows[i];
      }
    }
    return null;
  }

  @override
  Future<Member?> updateMember(
    String memberId, {
    String? role,
    String? artistId,
  }) => _mutate(memberId, (m) => m.copyWith(role: role, artistId: artistId));

  @override
  Future<Member?> revoke(String memberId) => _mutate(
    memberId,
    (m) => m.status == 'revoked'
        ? m
        : m.copyWith(status: 'revoked', revokedAt: DateTime.now().toUtc()),
  );

  @override
  Future<Member?> resendInvite(String memberId, DateTime newExpiresAt) async {
    final member = await byId(memberId);
    if (member == null || member.resendsLeft <= 0) return null;
    return _mutate(
      memberId,
      (m) =>
          m.copyWith(expiresAt: newExpiresAt, resendsLeft: m.resendsLeft - 1),
    );
  }

  @override
  Future<Member?> activate(String memberId, String accountId) async {
    final i = _rows.indexWhere((m) => m.id == memberId);
    if (i < 0) return null;
    final m = _rows[i];
    // The Postgres WHERE, word for word: still invited, window not closed
    // (`expires_at IS NULL OR expires_at > now()`).
    final open =
        m.status == 'invited' &&
        (m.expiresAt == null || m.expiresAt!.isAfter(DateTime.now().toUtc()));
    if (!open) return null;
    return _rows[i] = m.copyWith(
      accountId: accountId,
      status: 'active',
      acceptedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> decline(String memberId) async {
    final i = _rows.indexWhere(
      (m) => m.id == memberId && m.status == 'invited',
    );
    if (i < 0) return;
    final m = _rows[i];
    if (m.accountId == null) {
      _rows.removeAt(i);
    } else {
      _rows[i] = m.copyWith(
        status: 'revoked',
        revokedAt: DateTime.now().toUtc(),
      );
    }
  }
}

/// Local role-name constants (kept here so the repository has no dependency
/// on the capability layer).
abstract final class MemberRoleNames {
  static const owner = 'owner';
}
