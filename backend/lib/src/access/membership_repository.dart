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
  };

  Member copyWith({
    String? accountId,
    String? role,
    String? artistId,
    String? status,
    DateTime? acceptedAt,
    DateTime? revokedAt,
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

  /// Mark every membership of the account revoked (account deletion, T53).
  Future<void> revokeAllForAccount(String accountId);
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
  Future<void> revokeAllForAccount(String accountId) async {
    final now = DateTime.now().toUtc();
    for (var i = 0; i < _rows.length; i++) {
      if (_rows[i].accountId == accountId && _rows[i].status != 'revoked') {
        _rows[i] = _rows[i].copyWith(status: 'revoked', revokedAt: now);
      }
    }
  }
}

/// Local role-name constants (kept here so the repository has no dependency
/// on the capability layer).
abstract final class MemberRoleNames {
  static const owner = 'owner';
}
