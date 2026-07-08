import 'dart:math';

import '../appointments/appointment_repository.dart';
import '../auth/auth_repository.dart';
import '../auth/provider_auth_repository.dart';
import 'clients_repository.dart';
import 'provider_audit_log.dart';

typedef ClientsResult = ({bool ok, String? error, Map<String, dynamic>? data});

/// The salon client base (module `clients` C1 — docs/design/clients-c1.md).
///
/// Ownership: every entry point resolves the caller's provider account and
/// requires `account.providerId == providerId` (threat T45; deny by default).
/// The capability gate is named `clients.view` from day one — until the
/// `access` module ships memberships, "has the capability" == "owns the
/// salon", exactly like every other pro surface.
///
/// Reads of the base are AUDITED (T46/T39): `clients.list` and `clients.view`
/// rows in the provider audit log.
///
/// Stats are computed salon-scoped aggregates over appointments — a client's
/// bookings resolve by `userId`, plus (for guests) by `clientPhone` on
/// manual bookings (`userId == 'manual'`).
class ClientsService {
  ClientsService(
    this._providerAuth,
    this._users,
    this._clients,
    this._appointments,
    this._audit,
  );

  final ProviderAuthRepository _providerAuth;
  final AuthRepository _users;
  final ClientsRepository _clients;
  final AppointmentRepository _appointments;
  final ProviderAuditLogRepository _audit;

  static const presetTags = ['VIP', 'Fidèle', 'À risque'];
  static const maxTags = 10;
  static const maxTagLength = 24;
  static const maxNoteLength = 500;

  final _random = Random();
  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_'
      '${_random.nextInt(1 << 32)}';

  /// Resolves + authorizes the caller for [providerId] (capability
  /// `clients.view`). Null → forbidden.
  Future<ProviderAccount?> _authorized(
    String accountId,
    String providerId,
  ) async {
    final account = await _providerAuth.accountById(accountId);
    if (account?.providerId != providerId) return null;
    return account;
  }

  // ---- List ----------------------------------------------------------------

  Future<ClientsResult> list(
    String accountId,
    String providerId, {
    String? query,
    String? tag,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (await _authorized(accountId, providerId) == null) {
      return (ok: false, error: 'forbidden', data: null);
    }
    final effectivePage = max(1, page);
    final effectiveSize = pageSize.clamp(1, 50);
    final r = await _clients.list(
      providerId,
      query: query,
      tag: tag,
      page: effectivePage,
      pageSize: effectiveSize,
    );

    final stats = await _statsByClient(providerId, r.items);
    final items = [
      for (final c in r.items)
        {
          ..._shape(c),
          'visits': stats[c['id']]?.visits ?? 0,
          'noShows': stats[c['id']]?.noShows ?? 0,
        },
    ];

    await _audit.log(
      providerId: providerId,
      actorAccountId: accountId,
      action: 'clients.list',
      meta: {
        if (query != null && query.isNotEmpty) 'query': query,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
        'page': effectivePage,
      },
    );

    return (
      ok: true,
      error: null,
      data: {
        'items': items,
        'page': effectivePage,
        'pageSize': effectiveSize,
        'total': r.total,
        if (effectivePage == 1)
          'availableTags': {
            ...presetTags,
            ...await _clients.tagsFor(providerId),
          }.toList(),
      },
    );
  }

  // ---- Card ----------------------------------------------------------------

  Future<ClientsResult> card(
    String accountId,
    String providerId,
    String clientId,
  ) async {
    if (await _authorized(accountId, providerId) == null) {
      return (ok: false, error: 'forbidden', data: null);
    }
    final client = await _clients.byId(providerId, clientId);
    if (client == null) return (ok: false, error: 'not_found', data: null);

    final visits = await _visitsOf(providerId, client);
    var completed = 0;
    var noShows = 0;
    var cancellations = 0;
    num spent = 0;
    Map<String, dynamic>? upcoming;
    final now = DateTime.now().toUtc();
    for (final a in visits) {
      switch (a['status']) {
        case 'completed':
          completed++;
          spent += (a['totalPrice'] as num?) ?? 0;
        case 'noShow':
          noShows++;
        case 'cancelled':
          cancellations++;
        case 'pending' || 'confirmed':
          final at = DateTime.tryParse(a['appointmentDate'] as String? ?? '');
          if (at != null && at.toUtc().isAfter(now)) {
            // visits are newest-first → keep the SOONEST future one.
            upcoming = a;
          }
      }
    }

    final notes = await _clients.notesFor(clientId);

    await _audit.log(
      providerId: providerId,
      actorAccountId: accountId,
      action: 'clients.view',
      targetId: clientId,
    );

    return (
      ok: true,
      error: null,
      data: {
        ..._shape(client),
        'stats': {
          'visits': completed,
          'spentFcfa': spent,
          'noShows': noShows,
          'cancellations': cancellations,
        },
        if (upcoming != null) 'upcoming': upcoming,
        'notes': [for (final n in notes) await _shapeNote(n)],
      },
    );
  }

  Future<ClientsResult> visits(
    String accountId,
    String providerId,
    String clientId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    if (await _authorized(accountId, providerId) == null) {
      return (ok: false, error: 'forbidden', data: null);
    }
    final client = await _clients.byId(providerId, clientId);
    if (client == null) return (ok: false, error: 'not_found', data: null);

    final all = await _visitsOf(providerId, client);
    final effectivePage = max(1, page);
    final effectiveSize = pageSize.clamp(1, 50);
    final start = (effectivePage - 1) * effectiveSize;
    final items = start >= all.length
        ? <Map<String, dynamic>>[]
        : all.sublist(start, min(start + effectiveSize, all.length));
    return (
      ok: true,
      error: null,
      data: {
        'items': items,
        'page': effectivePage,
        'pageSize': effectiveSize,
        'total': all.length,
      },
    );
  }

  // ---- Manual add (docs/modules/clients.md §11.4: phone REQUIRED) ----------

  Future<ClientsResult> addClient(
    String accountId,
    String providerId, {
    required String name,
    required String phone,
    String? note,
  }) async {
    if (await _authorized(accountId, providerId) == null) {
      return (ok: false, error: 'forbidden', data: null);
    }
    final existing = await _clients.byPhone(providerId, phone);
    if (existing != null) {
      return (
        ok: false,
        error: 'client_exists',
        data: {'clientId': existing['id']},
      );
    }
    final client = await _clients.create({
      'id': _newId('client'),
      'providerId': providerId,
      'userId': null,
      'displayName': name,
      'phone': phone,
      'tags': const <String>[],
      'lastVisitAt': null,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    if (note != null && note.trim().isNotEmpty) {
      await _addNoteRow(client['id'] as String, accountId, note.trim());
    }
    return (ok: true, error: null, data: _shape(client));
  }

  // ---- Tags ------------------------------------------------------------------

  Future<ClientsResult> updateTags(
    String accountId,
    String providerId,
    String clientId,
    List<String> tags,
  ) async {
    if (await _authorized(accountId, providerId) == null) {
      return (ok: false, error: 'forbidden', data: null);
    }
    final cleaned = <String>[];
    for (final raw in tags) {
      final t = raw.trim();
      if (t.isEmpty || t.length > maxTagLength) {
        return (ok: false, error: 'invalid_tags', data: null);
      }
      if (!cleaned.contains(t)) cleaned.add(t);
    }
    if (cleaned.length > maxTags) {
      return (ok: false, error: 'invalid_tags', data: null);
    }
    final updated = await _clients.updateTags(providerId, clientId, cleaned);
    if (updated == null) return (ok: false, error: 'not_found', data: null);
    return (ok: true, error: null, data: _shape(updated));
  }

  // ---- Notes -----------------------------------------------------------------

  Future<ClientsResult> addNote(
    String accountId,
    String providerId,
    String clientId,
    String body,
  ) async {
    if (await _authorized(accountId, providerId) == null) {
      return (ok: false, error: 'forbidden', data: null);
    }
    final client = await _clients.byId(providerId, clientId);
    if (client == null) return (ok: false, error: 'not_found', data: null);
    final trimmed = body.trim();
    if (trimmed.isEmpty || trimmed.length > maxNoteLength) {
      return (ok: false, error: 'note_too_long', data: null);
    }
    final note = await _addNoteRow(clientId, accountId, trimmed);
    return (ok: true, error: null, data: await _shapeNote(note));
  }

  Future<ClientsResult> deleteNote(
    String accountId,
    String providerId,
    String clientId,
    String noteId,
  ) async {
    if (await _authorized(accountId, providerId) == null) {
      return (ok: false, error: 'forbidden', data: null);
    }
    final client = await _clients.byId(providerId, clientId);
    if (client == null) return (ok: false, error: 'not_found', data: null);
    final note = await _clients.noteById(clientId, noteId);
    if (note == null) return (ok: false, error: 'not_found', data: null);
    // Author or owner. Today every caller that reaches here manages the salon
    // (== owner); the author check becomes meaningful with `access` members.
    await _clients.deleteNote(clientId, noteId);
    return (ok: true, error: null, data: null);
  }

  // ---- Privacy (threat T48) --------------------------------------------------

  /// Deleted-account anonymization across every salon (called from
  /// `DELETE /me` right after the account deletion).
  Future<void> anonymizeUser(String userId) => _clients.anonymizeUser(userId);

  // ---- Derived upkeep (bookings build the base) -----------------------------

  /// Booking created → make sure the client row exists ("derived, not
  /// entered"). Platform users key by `userId`; manual bookings by
  /// `clientPhone` (no phone → no row, journal-only guest). Never throws into
  /// the booking flow.
  Future<void> recordBooking(Map<String, dynamic> appointment) async {
    try {
      final providerId = appointment['providerId'] as String?;
      if (providerId == null) return;
      final userId = appointment['userId'] as String?;
      if (userId != null && userId != 'manual') {
        if (await _clients.byUserId(providerId, userId) != null) return;
        final user = await _users.userById(userId);
        // A linked client's phone is stored only when VERIFIED (T49 bar), and
        // only if no guest row already holds it (that merge is C3's job —
        // colliding here would break the (provider, phone) uniqueness).
        final verifiedPhone = (user?.phoneVerified ?? false)
            ? user?.phoneNumber
            : null;
        final phoneFree =
            verifiedPhone == null ||
            await _clients.byPhone(providerId, verifiedPhone) == null;
        await _clients.create({
          'id': _newId('client'),
          'providerId': providerId,
          'userId': userId,
          'displayName': user?.name ?? 'Client',
          'phone': phoneFree ? verifiedPhone : null,
          'tags': const <String>[],
          'lastVisitAt': null,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
        return;
      }
      final phone = appointment['clientPhone'] as String?;
      if (phone == null || phone.isEmpty) return;
      if (await _clients.byPhone(providerId, phone) != null) return;
      await _clients.create({
        'id': _newId('client'),
        'providerId': providerId,
        'userId': null,
        'displayName': (appointment['clientName'] as String?) ?? 'Client',
        'phone': phone,
        'tags': const <String>[],
        'lastVisitAt': null,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      /* best-effort — never break booking */
    }
  }

  /// Completed visit → bump the client's `lastVisitAt` (list sort).
  Future<void> recordCompletion(Map<String, dynamic> appointment) async {
    try {
      final providerId = appointment['providerId'] as String?;
      final at = DateTime.tryParse(
        appointment['appointmentDate'] as String? ?? '',
      );
      if (providerId == null || at == null) return;
      final client = await _resolveClient(providerId, appointment);
      if (client == null) return;
      await _clients.touchLastVisit(providerId, client['id'] as String, at);
    } catch (_) {
      /* best-effort */
    }
  }

  /// Provider appointment payload enrichment: `salonClientId` +
  /// `clientNoShowCount` (the accept-screen badge — clients-c1.md §5).
  Future<List<Map<String, dynamic>>> enrichForProvider(
    String providerId,
    List<Map<String, dynamic>> appointments,
  ) async {
    if (appointments.isEmpty) return appointments;
    final all = await _appointments.listForProvider(providerId);
    final noShowsByUser = <String, int>{};
    final noShowsByPhone = <String, int>{};
    for (final a in all) {
      if (a['status'] != 'noShow') continue;
      final uid = a['userId'] as String?;
      if (uid != null && uid != 'manual') {
        noShowsByUser[uid] = (noShowsByUser[uid] ?? 0) + 1;
      } else if (a['clientPhone'] is String) {
        final p = a['clientPhone'] as String;
        noShowsByPhone[p] = (noShowsByPhone[p] ?? 0) + 1;
      }
    }
    return [
      for (final a in appointments)
        {
          ...a,
          ...await _identityOf(providerId, a),
          'clientNoShowCount': switch (a['userId']) {
            final String uid when uid != 'manual' => noShowsByUser[uid] ?? 0,
            _ => noShowsByPhone[a['clientPhone']] ?? 0,
          },
        },
    ];
  }

  Future<Map<String, dynamic>> _identityOf(
    String providerId,
    Map<String, dynamic> appointment,
  ) async {
    final client = await _resolveClient(providerId, appointment);
    return {if (client != null) 'salonClientId': client['id']};
  }

  Future<Map<String, dynamic>?> _resolveClient(
    String providerId,
    Map<String, dynamic> appointment,
  ) async {
    final userId = appointment['userId'] as String?;
    if (userId != null && userId != 'manual') {
      return _clients.byUserId(providerId, userId);
    }
    final phone = appointment['clientPhone'] as String?;
    if (phone == null || phone.isEmpty) return null;
    return _clients.byPhone(providerId, phone);
  }

  // ---- Internals -------------------------------------------------------------

  /// A client's appointments at THIS salon (never cross-salon — T45), newest
  /// first: by `userId` for linked clients, plus by guest phone.
  Future<List<Map<String, dynamic>>> _visitsOf(
    String providerId,
    Map<String, dynamic> client,
  ) async {
    final all = await _appointments.listForProvider(providerId);
    final userId = client['userId'] as String?;
    final phone = client['phone'] as String?;
    return [
      for (final a in all)
        if ((userId != null && a['userId'] == userId) ||
            (phone != null &&
                a['userId'] == 'manual' &&
                a['clientPhone'] == phone))
          a,
    ];
  }

  Future<Map<String, ({int visits, int noShows})>> _statsByClient(
    String providerId,
    List<Map<String, dynamic>> clients,
  ) async {
    if (clients.isEmpty) return {};
    final all = await _appointments.listForProvider(providerId);
    final result = <String, ({int visits, int noShows})>{};
    for (final c in clients) {
      final userId = c['userId'] as String?;
      final phone = c['phone'] as String?;
      var visits = 0;
      var noShows = 0;
      for (final a in all) {
        final mine =
            (userId != null && a['userId'] == userId) ||
            (phone != null &&
                a['userId'] == 'manual' &&
                a['clientPhone'] == phone);
        if (!mine) continue;
        if (a['status'] == 'completed') visits++;
        if (a['status'] == 'noShow') noShows++;
      }
      result[c['id'] as String] = (visits: visits, noShows: noShows);
    }
    return result;
  }

  Future<Map<String, dynamic>> _addNoteRow(
    String clientId,
    String authorAccountId,
    String body,
  ) => _clients.addNote({
    'id': _newId('note'),
    'clientId': clientId,
    'authorAccountId': authorAccountId,
    'body': body,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  });

  Future<Map<String, dynamic>> _shapeNote(Map<String, dynamic> note) async {
    final author = await _providerAuth.accountById(
      note['authorAccountId'] as String,
    );
    return {
      'id': note['id'],
      'authorName': author?.name ?? author?.businessName ?? 'Équipe',
      'body': note['body'],
      'createdAt': note['createdAt'],
    };
  }

  /// Public DTO shape — internal linkage stays internal.
  Map<String, dynamic> _shape(Map<String, dynamic> client) => {
    'id': client['id'],
    'displayName': client['displayName'],
    'phone': client['phone'],
    'tags': client['tags'],
    'lastVisitAt': client['lastVisitAt'],
    'linked': client['userId'] != null,
    'createdAt': client['createdAt'],
  };
}
