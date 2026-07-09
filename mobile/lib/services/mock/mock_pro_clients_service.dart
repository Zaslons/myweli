import '../../core/constants/app_constants.dart';
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
      lastVisitAt: DateTime.now().subtract(const Duration(days: 3)),
      linked: true,
      visits: 12,
      noShows: 0,
    ),
    SalonClient(
      id: 'sc2',
      displayName: 'Koffi Yao',
      phone: '+2250700000002',
      tags: const [],
      lastVisitAt: DateTime.now().subtract(const Duration(days: 12)),
      linked: true,
      visits: 3,
      noShows: 2,
    ),
    const SalonClient(
      id: 'sc3',
      displayName: 'Tante Marie',
      phone: '+2250700000003',
      tags: ['Fidèle'],
      linked: false,
      visits: 1,
      noShows: 0,
    ),
  ];
  final Map<String, List<SalonClientNote>> _notes = {
    'sc1': [
      SalonClientNote(
        id: 'note1',
        authorName: 'Vous',
        body: 'Préfère Awa. Allergique à l’ammoniaque.',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
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
    final filtered = _clients
        .where((c) => tag == null || tag.isEmpty || c.tags.contains(tag))
        .where((c) {
      if (q.isEmpty) return true;
      if (c.displayName.toLowerCase().contains(q)) return true;
      return qDigits.length >= 2 &&
          c.phone != null &&
          _digits(c.phone!).contains(qDigits);
    }).toList()
      ..sort((a, b) {
        if (a.lastVisitAt == null && b.lastVisitAt == null) return 0;
        if (a.lastVisitAt == null) return 1;
        if (b.lastVisitAt == null) return -1;
        return b.lastVisitAt!.compareTo(a.lastVisitAt!);
      });
    final start = (page - 1) * pageSize;
    final items = start >= filtered.length
        ? <SalonClient>[]
        : filtered.sublist(
            start,
            (start + pageSize).clamp(0, filtered.length),
          );
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
    return ApiResponse.success(
      SalonClientCard(
        client: client,
        stats: SalonClientStats(
          visits: client.visits,
          spentFcfa: client.visits * 15000,
          noShows: client.noShows,
          cancellations: 0,
        ),
        notes: List.of(_notes[clientId] ?? const []),
      ),
    );
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
    return ApiResponse.success([
      for (var i = 0; i < client.visits.clamp(0, 5); i++)
        Appointment(
          id: 'visit_${clientId}_$i',
          userId: client.linked ? 'user_$clientId' : 'manual',
          providerId: providerId,
          serviceIds: const ['service_1'],
          appointmentDate: DateTime.now().subtract(Duration(days: 7 * (i + 1))),
          status: AppointmentStatus.completed,
          totalPrice: 15000,
          createdAt: DateTime.now().subtract(Duration(days: 7 * (i + 1))),
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
          createdAt: DateTime.now(),
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
    return ApiResponse.success(_clients[i]);
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
      createdAt: DateTime.now(),
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
