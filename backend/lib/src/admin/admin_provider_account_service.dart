import '../access/membership_repository.dart';
import '../auth/provider_auth_repository.dart';
import '../provider_account_service.dart';
import '../providers_repository.dart';
import 'admin_kyc_service.dart' show AdminResult;
import 'audit_log_repository.dart';

/// Erase a Pro account on a support request, and find it first (B0.25's
/// server half, decisions 141 and 142). Admin-only: both routes sit behind
/// the `/admin` gate (T17); threat T83.
///
/// **The erase IS `deleteAccount`.** Every step of a Pro's own « Supprimer
/// mon compte » lives in that one method — the demo lock, the bookings gate
/// over every owned salon, the unpublish and the contact wipe, the KYC
/// objects, devices, notifications, the Apple revoke, the identity, the
/// memberships, the re-hide. A second implementation here would be a second
/// chance to miss one, which is how the consumer cascade was missed the first
/// time. So this holds the [ProviderAccountService] it is GIVEN — the
/// production singleton, whose optional dependencies are all wired; a fresh
/// construction would compile and silently skip devices, notifications,
/// Apple, the validations, the place notices and the rebuild — and calls it,
/// once, unchanged. Never the repository's own `deleteAccount`: that is the
/// bypass of the demo lock T69 counts.
///
/// No `dart_frog`, no SQL (BACKEND.md §1).
///
/// Design: docs/design/admin-pro-account-erase.md.
class AdminProviderAccountService {
  AdminProviderAccountService(
    this._accounts,
    this._auth,
    this._memberships,
    this._providers,
    this._audit,
  );

  /// The production singleton (`dependencies.dart`), never a new one.
  final ProviderAccountService _accounts;

  /// Reads only: the account by id and by e-mail.
  final ProviderAuthRepository _auth;
  final MembershipRepository _memberships;
  final ProvidersRepository _providers;
  final AuditLogRepository _audit;

  /// The page's two support paths (docs/design/web-pro-account-deletion.md
  /// §5.1). Closed: the audit log is kept with no limit, so a typed name in
  /// a free-text reason would move personal data into it rather than erase it.
  static const Set<String> reasons = {
    'support_no_sign_in',
    'support_access_removed',
  };

  /// The case number the owner's case record carries (§10.1). Not personal
  /// data; strict, untrimmed — the procedure generates it.
  static final RegExp caseRefPattern = RegExp(r'^MWP-[A-Z0-9]{6}$');

  /// The account behind one EXACT address — never a prefix, never a list —
  /// with what the procedure needs and nothing more: the id the erase takes,
  /// the STORED address (the challenge goes there, and it is the erase's
  /// `confirmEmail`), when it was made, the salons the erase will hide and
  /// every membership row. Left out: the name, phone, address, KYC documents
  /// and verification state — every field returned lands in a terminal.
  ///
  /// Not audited, like every read-only admin support view. `invalid_input`
  /// (trimmed, 3–254 characters, exactly one `@`), `not_found`.
  Future<AdminResult> lookup(String? email) async {
    final address = email?.trim() ?? '';
    if (address.length < 3 ||
        address.length > 254 ||
        '@'.allMatches(address).length != 1) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final account = await _auth.accountByEmail(address);
    if (account == null) return (ok: false, error: 'not_found', data: null);

    final rows = await _memberships.listForAccount(account.id);
    // OWNED by `deleteAccount`'s own definition — the scalar link plus the
    // active owner rows — so the owner sees the erase's blast radius before
    // the yes, and no second copy can drift from it.
    final owned = ProviderAccountService.ownedSalonIds(account, rows);
    // One read for every salon named (BACKEND.md §4: no N+1).
    final salons = {
      for (final s in await _providers.byIds(
        {...owned, for (final m in rows) m.providerId}.toList(),
      ))
        s['id'] as String: s,
    };
    return (
      ok: true,
      error: null,
      data: {
        'accountId': account.id,
        'email': account.email,
        'createdAt': account.createdAt.toUtc().toIso8601String(),
        'ownedSalons': [
          for (final id in owned)
            {
              'id': id,
              'name': salons[id]?['name'],
              'status': salons[id]?['status'],
            },
        ],
        'memberships': [
          for (final m in rows)
            {
              'providerId': m.providerId,
              'salonName': salons[m.providerId]?['name'],
              'role': m.role,
              'status': m.status,
            },
        ],
      },
    );
  }

  /// Erase account [id] on [adminId]'s authority. In order (§4.2):
  ///
  /// 0. every field checked before anything is read — `invalid_input`;
  /// 1. the account, or `not_found`;
  /// 2. [confirmEmail] against the STORED address, trimmed and lower-cased
  ///    — an operator-error guard against a wrongly copied id, not an
  ///    attacker guard (any admin reads the address through [lookup]);
  ///    none on file, or another one: `confirmation_mismatch`;
  /// 3. `deleteAccount`, unchanged: `demo_account_locked` and
  ///    `future_bookings` pass through, with no override; `forbidden` (a
  ///    concurrent call deleted the identity first) is `not_found`;
  /// 4. on success ONLY, one `provider_account.erase` row: the id, the
  ///    closed reason, the case number — no e-mail, no name, no salon name.
  ///    A row claiming an erase that did not happen is worse than none.
  ///
  /// A repeat after success is `not_found` at step 1 and writes nothing.
  Future<AdminResult> erase(
    String adminId,
    String id, {
    String? confirmEmail,
    String? reason,
    String? caseRef,
  }) async {
    final confirm = confirmEmail?.trim().toLowerCase() ?? '';
    if (confirm.isEmpty ||
        !reasons.contains(reason) ||
        caseRef == null ||
        !caseRefPattern.hasMatch(caseRef)) {
      return (ok: false, error: 'invalid_input', data: null);
    }

    final account = await _auth.accountById(id);
    if (account == null) return (ok: false, error: 'not_found', data: null);

    final stored = account.email?.trim().toLowerCase();
    if (stored == null || stored.isEmpty || stored != confirm) {
      return (ok: false, error: 'confirmation_mismatch', data: null);
    }

    final r = await _accounts.deleteAccount(id);
    if (!r.ok) {
      return (
        ok: false,
        error: r.error == 'forbidden' ? 'not_found' : r.error,
        data: null,
      );
    }

    await _audit.append((
      actorAdminId: adminId,
      action: 'provider_account.erase',
      targetType: 'provider_account',
      targetId: id,
      reason: reason,
      // The identity is gone: this row is the only record it existed. The
      // case number ties it to the owner's case record, kept outside git
      // with no name and no address — a tombstone, not a copy.
      metadata: {'caseRef': caseRef},
    ));
    return (ok: true, error: null, data: null);
  }
}
