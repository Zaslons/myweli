import '../../core/constants/app_constants.dart';
import '../../core/utils/app_clock.dart';
import '../../core/utils/phone_numbering.dart';
import '../../core/utils/validators.dart';
import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/salon_client.dart';
import '../interfaces/pro_clients_service_interface.dart';

/// Mock salon client base — realistic latency, pagination, dedupe and error
/// behavior so the UI is built against the real contract
/// (docs/design/clients-c1.md; guardrails: mock realism).
class MockProClientsService implements ProClientsServiceInterface {
  static const int pageSize = 20;

  final List<SalonClient> _clients = [
    SalonClient(
      id: 'sc1',
      displayName: 'Aïcha Koné',
      phone: '+2250700000001',
      tags: const ['VIP'],
      lastVisitAt: AppClock.now().subtract(const Duration(days: 3)),
      linked: true,
      visits: 12,
      noShows: 0,
    ),
    SalonClient(
      id: 'sc2',
      displayName: 'Koffi Yao',
      phone: '+2250700000002',
      tags: const [],
      lastVisitAt: AppClock.now().subtract(const Duration(days: 12)),
      linked: true,
      visits: 3,
      noShows: 2,
    ),
    const SalonClient(
      id: 'sc3',
      displayName: 'Tante Marie',
      phone: _guestSeedPhone,
      tags: ['Fidèle'],
      linked: false,
      visits: 1,
      noShows: 0,
    ),
  ];

  /// The seeded guest's number — her walk-in history is filed under it.
  static const String _guestSeedPhone = '+2250700000003';

  /// Each salon's walk-in bookings (`userId == 'manual'`). A guest card finds
  /// its history BY ITS NUMBER — the server's `_visitsOf` rule — so a number
  /// change has to move them, or the card comes back empty
  /// (phone-leftovers.md §8). Seeded per salon on its first read with the
  /// seeded guest's visit, under the number she was seeded with: another
  /// salon's bookings are its own, and a change at one salon never moves them
  /// (T45).
  final Map<String, List<Appointment>> _walkIns = {};

  List<Appointment> _walkInsOf(String providerId) =>
      _walkIns.putIfAbsent(providerId, () {
        final at = AppClock.now().subtract(const Duration(days: 30));
        return [
          Appointment(
            id: 'walkin_${providerId}_1',
            userId: 'manual',
            providerId: providerId,
            serviceIds: const ['service_1'],
            appointmentDate: at,
            status: AppointmentStatus.completed,
            totalPrice: 15000,
            clientName: 'Tante Marie',
            clientPhone: _guestSeedPhone,
            createdAt: at,
          ),
        ];
      });

  /// A guest card's history at [providerId]: the salon's walk-ins under its
  /// number, newest first.
  List<Appointment> _historyOf(String providerId, SalonClient client) =>
      _walkInsOf(providerId)
          .where((a) => a.userId == 'manual' && a.clientPhone == client.phone)
          .toList()
        ..sort((a, b) => b.appointmentDate.compareTo(a.appointmentDate));

  /// A client as a CARD is sent (`GET`, every `PATCH` answer): with
  /// `phoneEditable`, the server's rule — a guest card that has a number
  /// (phone-leftovers.md §8). List rows go without it, as the server's do.
  SalonClient _asCard(SalonClient client) =>
      client.copyWith(phoneEditable: !client.linked && client.phone != null);

  /// The card as `GET …/clients/{id}` (and the number change) answers it. A
  /// guest's stats are counted from its history, so they follow the number.
  SalonClientCard _cardOf(String providerId, SalonClient client) {
    final SalonClientStats stats;
    if (client.linked) {
      stats = SalonClientStats(
        visits: client.visits,
        spentFcfa: client.visits * 15000,
        noShows: client.noShows,
        cancellations: 0,
      );
    } else {
      final history = _historyOf(providerId, client);
      final done = history.where(
        (a) => a.status == AppointmentStatus.completed,
      );
      stats = SalonClientStats(
        visits: done.length,
        spentFcfa: done.fold<num>(0, (sum, a) => sum + a.totalPrice),
        noShows: history
            .where((a) => a.status == AppointmentStatus.noShow)
            .length,
        cancellations: history
            .where((a) => a.status == AppointmentStatus.cancelled)
            .length,
      );
    }
    return SalonClientCard(
      client: _asCard(client),
      stats: stats,
      notes: List.of(_notes[client.id] ?? const []),
    );
  }

  final Map<String, List<SalonClientNote>> _notes = {
    'sc1': [
      SalonClientNote(
        id: 'note1',
        authorName: 'Vous',
        body: 'Préfère Awa. Allergique à l’ammoniaque.',
        createdAt: AppClock.now().subtract(const Duration(days: 3)),
      ),
    ],
  };
  int _seq = 4;

  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  @override
  Future<ApiResponse<SalonClientsPage>> listClients(
    String providerId, {
    String? query,
    String? tag,
    int page = 1,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    final q = (query ?? '').trim().toLowerCase();
    final qDigits = _digits(q);
    final filtered =
        _clients
            .where((c) => tag == null || tag.isEmpty || c.tags.contains(tag))
            .where((c) {
              if (q.isEmpty) return true;
              if (c.displayName.toLowerCase().contains(q)) return true;
              return qDigits.length >= 2 &&
                  c.phone != null &&
                  _digits(c.phone!).contains(qDigits);
            })
            .toList()
          ..sort((a, b) {
            if (a.lastVisitAt == null && b.lastVisitAt == null) return 0;
            if (a.lastVisitAt == null) return 1;
            if (b.lastVisitAt == null) return -1;
            return b.lastVisitAt!.compareTo(a.lastVisitAt!);
          });
    final start = (page - 1) * pageSize;
    final items = start >= filtered.length
        ? <SalonClient>[]
        : filtered.sublist(start, (start + pageSize).clamp(0, filtered.length));
    return ApiResponse.success(
      SalonClientsPage(
        items: items,
        page: page,
        total: filtered.length,
        availableTags: page == 1
            ? {
                ...salonClientPresetTags,
                for (final c in _clients) ...c.tags,
              }.toList()
            : const [],
      ),
    );
  }

  @override
  Future<ApiResponse<SalonClientCard>> getCard(
    String providerId,
    String clientId,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    final client = _byId(clientId);
    if (client == null) {
      return ApiResponse.error('Client introuvable.', code: 'not_found');
    }
    return ApiResponse.success(_cardOf(providerId, client));
  }

  @override
  Future<ApiResponse<List<Appointment>>> getVisits(
    String providerId,
    String clientId, {
    int page = 1,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    final client = _byId(clientId);
    if (client == null) {
      return ApiResponse.error('Client introuvable.', code: 'not_found');
    }
    if (page > 1) return ApiResponse.success(const []);
    if (!client.linked) {
      return ApiResponse.success(_historyOf(providerId, client));
    }
    // A linked card's history is found by its account, not its number — the
    // mock draws it from the seeded count.
    return ApiResponse.success([
      for (var i = 0; i < client.visits.clamp(0, 5); i++)
        Appointment(
          id: 'visit_${clientId}_$i',
          userId: 'user_$clientId',
          providerId: providerId,
          serviceIds: const ['service_1'],
          appointmentDate: AppClock.now().subtract(Duration(days: 7 * (i + 1))),
          status: AppointmentStatus.completed,
          totalPrice: 15000,
          createdAt: AppClock.now().subtract(Duration(days: 7 * (i + 1))),
        ),
    ]);
  }

  @override
  Future<ApiResponse<String>> addClient(
    String providerId, {
    required String name,
    required String phone,
    String? note,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    for (final c in _clients) {
      if (c.phone == phone) {
        return ApiResponse(
          success: false,
          data: c.id, // the EXISTING card — UI opens it
          error: 'Ce numéro existe déjà.',
          code: 'client_exists',
        );
      }
    }
    final client = SalonClient(
      id: 'sc${_seq++}',
      displayName: name,
      phone: phone,
      tags: const [],
      linked: false,
    );
    _clients.add(client);
    if (note != null && note.trim().isNotEmpty) {
      (_notes[client.id] ??= []).insert(
        0,
        SalonClientNote(
          id: 'note${_seq++}',
          authorName: 'Vous',
          body: note.trim(),
          createdAt: AppClock.now(),
        ),
      );
    }
    return ApiResponse.success(client.id, message: 'Client ajouté');
  }

  @override
  Future<ApiResponse<SalonClient>> updateTags(
    String providerId,
    String clientId,
    List<String> tags,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    final i = _clients.indexWhere((c) => c.id == clientId);
    if (i < 0) return ApiResponse.error('Client introuvable.');
    if (tags.length > 10 || tags.any((t) => t.isEmpty || t.length > 24)) {
      return ApiResponse.error('Tags invalides.', code: 'invalid_tags');
    }
    _clients[i] = _clients[i].copyWith(tags: tags);
    return ApiResponse.success(_asCard(_clients[i]));
  }

  @override
  Future<ApiResponse<SalonClientPhoneChange>> updatePhone(
    String providerId,
    String clientId,
    String phone,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    final i = _clients.indexWhere((c) => c.id == clientId);
    if (i < 0) {
      return ApiResponse.error('Client introuvable.', code: 'not_found');
    }
    final client = _clients[i];
    // A card linked to an account keeps the account's number.
    if (client.linked) {
      return ApiResponse.error(
        'Numéro du compte client.',
        code: 'client_linked',
      );
    }
    // The server's rule (`isValidPhoneNumber`): E.164 with no separator, the
    // market's national length — empty refused, a guest card IS its number.
    final number = phone.trim();
    if (number != PhoneNumbering.normalize(number) ||
        Validators.phoneNumber(number) != null) {
      return ApiResponse.error('Numéro invalide.', code: 'invalid_phone');
    }
    if (number == client.phone) {
      return ApiResponse.success(
        SalonClientPhoneChange.changed(_cardOf(providerId, client)),
      );
    }
    for (final other in _clients) {
      if (other.id != clientId && other.phone == number) {
        return ApiResponse(
          success: false,
          data: SalonClientPhoneChange.taken(other.id),
          error: 'Ce numéro est déjà sur une autre fiche.',
          code: 'client_exists',
        );
      }
    }
    // One step, as the server's transaction: the card and THIS salon's
    // walk-ins under the old number take the new one.
    final walkIns = _walkInsOf(providerId);
    for (var j = 0; j < walkIns.length; j++) {
      final a = walkIns[j];
      if (a.userId == 'manual' && a.clientPhone == client.phone) {
        walkIns[j] = a.copyWith(clientPhone: number);
      }
    }
    _clients[i] = client.copyWith(phone: number);
    return ApiResponse.success(
      SalonClientPhoneChange.changed(_cardOf(providerId, _clients[i])),
      message: 'Numéro mis à jour',
    );
  }

  @override
  Future<ApiResponse<SalonClientNote>> addNote(
    String providerId,
    String clientId,
    String body,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    final trimmed = body.trim();
    if (trimmed.isEmpty || trimmed.length > 500) {
      return ApiResponse.error('Note trop longue.', code: 'note_too_long');
    }
    final note = SalonClientNote(
      id: 'note${_seq++}',
      authorName: 'Vous',
      body: trimmed,
      createdAt: AppClock.now(),
    );
    (_notes[clientId] ??= []).insert(0, note);
    return ApiResponse.success(note);
  }

  @override
  Future<ApiResponse<bool>> deleteNote(
    String providerId,
    String clientId,
    String noteId,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    _notes[clientId]?.removeWhere((n) => n.id == noteId);
    return ApiResponse.success(true);
  }

  SalonClient? _byId(String id) {
    for (final c in _clients) {
      if (c.id == id) return c;
    }
    return null;
  }
}
