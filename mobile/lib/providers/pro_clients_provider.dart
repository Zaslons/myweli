import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/access/pro_access_guard.dart';
import '../core/access/pro_salon_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/salon_id.dart';
import '../core/utils/submission_key.dart';
import '../models/appointment.dart';
import '../models/salon_client.dart';
import '../services/interfaces/pro_clients_service_interface.dart';

/// State for the salon client base (module `clients` C1 —
/// docs/design/clients-c1.md §5): the list (search / tag filter / infinite
/// scroll) and the open card (stats, notes, visits).
///
/// The open card is told when the salon creates a booking for its client
/// ([bookingCreated], docs/design/pro-journal-shows-new-booking.md §2.5).
class ProClientsProvider extends ChangeNotifier implements ShowsSalonBookings {
  final ProClientsServiceInterface _service = serviceLocator.proClientsService;

  /// One Idempotency-Key per note sent (docs/design/write-idempotency.md §4).
  final SubmissionKey _noteKey = SubmissionKey();

  // ---- List ------------------------------------------------------------

  final List<SalonClient> _clients = [];
  List<SalonClient> get clients => List.unmodifiable(_clients);
  int _total = 0;
  int get total => _total;
  bool get hasMore => _clients.length < _total;
  List<String> _availableTags = List.of(salonClientPresetTags);
  List<String> get availableTags => List.unmodifiable(_availableTags);
  String _query = '';
  String get query => _query;
  String _tag = '';
  String get tag => _tag;
  int _page = 1;
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;
  String? _error;
  String? get error => _error;

  /// The list read's own failure. [error] is also « Ajouter un client »'s:
  /// a refused add replaced the whole list with « Une erreur est survenue »
  /// once its sheet closed (B9.8).
  String? get loadError => _loadError;
  String? _loadError;

  /// True when the salon simply has no clients yet (vs an empty search).
  bool get isBaseEmpty => _total == 0 && _query.isEmpty && _tag.isEmpty;

  Future<void> load(SalonId providerId) async {
    final scope = _scope;
    _isLoading = true;
    _error = null;
    _loadError = null;
    notifyListeners();
    try {
      final r = await _service.listClients(
        providerId,
        query: _query.isEmpty ? null : _query,
        tag: _tag.isEmpty ? null : _tag,
      );
      if (scope != _scope) return;
      if (r.success && r.data != null) {
        _clients
          ..clear()
          ..addAll(r.data!.items);
        _total = r.data!.total;
        _page = 1;
        if (r.data!.availableTags.isNotEmpty) {
          _availableTags = r.data!.availableTags;
        }
      } else {
        _error = r.error ?? kGenericErrorMessage;
        _loadError = _error;
        ProAccessGuard.report(r.code);
      }
    } catch (e) {
      if (scope != _scope) return;
      _error = kGenericErrorMessage;
      _loadError = _error;
    } finally {
      if (scope == _scope) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore(SalonId providerId) async {
    final scope = _scope;
    if (_isLoadingMore || !hasMore) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final r = await _service.listClients(
        providerId,
        query: _query.isEmpty ? null : _query,
        tag: _tag.isEmpty ? null : _tag,
        page: _page + 1,
      );
      if (scope != _scope) return;
      if (r.success && r.data != null) {
        _clients.addAll(r.data!.items);
        _total = r.data!.total;
        _page += 1;
      }
      // A failed page (an error answer, or one that does not read — the
      // service says « Erreur », docs/design/export-unreadable-200.md §2.2):
      // nothing appended, the loaded list stays, and the next scroll asks
      // for the same page again.
    } finally {
      if (scope == _scope) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> search(SalonId providerId, String query) {
    _query = query.trim();
    return load(providerId);
  }

  /// Toggles [tag] (tapping the active chip clears the filter).
  Future<void> filterByTag(SalonId providerId, String tag) {
    _tag = _tag == tag ? '' : tag;
    return load(providerId);
  }

  /// Returns the new/existing client id, or null on failure. On a duplicate
  /// phone the id of the EXISTING card comes back and [lastAddWasDuplicate]
  /// is set (UI: toast « Ce numéro existe déjà » + open the card).
  bool _lastAddWasDuplicate = false;
  bool get lastAddWasDuplicate => _lastAddWasDuplicate;

  Future<String?> addClient(
    SalonId providerId, {
    required String name,
    required String phone,
    String? note,
  }) async {
    final scope = _scope;
    _error = null;
    _lastAddWasDuplicate = false;
    final r = await _service.addClient(
      providerId,
      name: name,
      phone: phone,
      note: note,
    );
    if (scope != _scope) return null;
    if (r.success && r.data != null) {
      await load(providerId);
      return r.data;
    }
    if (r.code == 'client_exists' && r.data != null) {
      _lastAddWasDuplicate = true;
      return r.data;
    }
    _error = r.error ?? 'Une erreur est survenue.';
    notifyListeners();
    return null;
  }

  // ---- Card ------------------------------------------------------------

  SalonClientCard? _card;
  SalonClientCard? get card => _card;
  List<Appointment> _visits = [];
  List<Appointment> get visits => List.unmodifiable(_visits);
  bool _cardLoading = false;
  bool get cardLoading => _cardLoading;
  String? _cardError;
  String? get cardError => _cardError;
  bool get cardNotFound => _cardError != null && _cardErrorCode == 'not_found';
  String? _cardErrorCode;

  /// Which card [_card] is, and the newest request for it — so that the quiet
  /// reload after a booking knows what to ask for, and its answer is dropped
  /// if another card was opened meanwhile.
  SalonId? _cardProviderId;
  String? _cardClientId;

  /// Whose card [card] is — the provider outlives the card's screen, and the
  /// next client's first frame still holds the last one (B9.8).
  String? get cardClientId => _cardClientId;
  int _cardRequest = 0;

  Future<void> loadCard(SalonId providerId, String clientId) async {
    final scope = _scope;
    _cardProviderId = providerId;
    _cardClientId = clientId;
    _cardRequest++;
    _cardLoading = true;
    _cardError = null;
    _card = null;
    _visits = [];
    notifyListeners();
    try {
      final r = await _service.getCard(providerId, clientId);
      if (scope != _scope) return;
      if (r.success && r.data != null) {
        _card = r.data;
        final v = await _service.getVisits(providerId, clientId);
        if (scope != _scope) return;
        _visits = v.data ?? [];
      } else {
        _cardError = r.error ?? 'Une erreur est survenue.';
        _cardErrorCode = r.code;
      }
    } catch (e) {
      if (scope != _scope) return;
      _cardError = kGenericErrorMessage;
    } finally {
      if (scope == _scope) {
        _cardLoading = false;
        notifyListeners();
      }
    }
  }

  /// The salon just created [booking]. When it is the open card's client's,
  /// « Prochain rendez-vous » and the visit history are out of date.
  ///
  /// « Its client's » is the server's own rule for a salon-entered booking:
  /// the same phone number (`ClientsService._visitsOf`). The card's « Nouvelle
  /// réservation » prefills that number, so the booking made from the card
  /// matches; a booking for anyone else leaves the card alone.
  @override
  void bookingCreated(Appointment booking) {
    final card = _card;
    final phone = booking.clientPhone;
    if (card == null || _cardLoading) return;
    if (booking.providerId != _cardProviderId) return;
    if (phone == null || phone.isEmpty || phone != card.client.phone) return;
    unawaited(_reloadCardQuietly());
  }

  /// A booking changed elsewhere (docs/design/app-pro-home-journal-fresh.md
  /// §2.1): when it is this card's client's — the same phone (the server's
  /// rule), a visit the card lists, or its upcoming booking — the card is read
  /// again, quietly (an absence moves its count, a visit its history).
  @override
  void bookingChanged(BookingChange change) {
    final card = _card;
    if (card == null || _cardLoading) return;
    if (change.providerId != _cardProviderId) return;
    final phone = change.clientPhone;
    final samePhone =
        phone != null && phone.isNotEmpty && phone == card.client.phone;
    final listed = _visits.any((v) => v.id == change.appointmentId);
    final upcoming = card.upcoming?['id'] == change.appointmentId;
    if (!samePhone && !listed && !upcoming) return;
    unawaited(_reloadCardQuietly());
  }

  /// The card and its visits again, with no loader: the card stays on screen
  /// and is replaced when both answers are in. A failure changes nothing.
  Future<void> _reloadCardQuietly() async {
    final providerId = _cardProviderId;
    final clientId = _cardClientId;
    if (providerId == null || clientId == null) return;
    final request = ++_cardRequest;
    try {
      final r = await _service.getCard(providerId, clientId);
      if (request != _cardRequest) return;
      if (!r.success || r.data == null) {
        ProAccessGuard.report(r.code);
        return;
      }
      final v = await _service.getVisits(providerId, clientId);
      if (request != _cardRequest) return;
      _card = r.data;
      if (v.success && v.data != null) _visits = v.data!;
      notifyListeners();
    } catch (_) {
      /* offline — the card stays as it is; reopening it reloads it */
    }
  }

  Future<bool> updateTags(
    SalonId providerId,
    String clientId,
    List<String> tags,
  ) async {
    final scope = _scope;
    final r = await _service.updateTags(providerId, clientId, tags);
    if (scope != _scope) return false;
    if (r.success && r.data != null && _card != null) {
      _card = _card!.copyWith(client: r.data);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Changes a GUEST card's number (docs/design/phone-leftovers.md §8); one
  /// linked to an account keeps the account's. The server moves the salon's
  /// walk-ins under the old number with it, so on success the card comes from
  /// its answer and the visits are read again before this returns — the sheet
  /// closes on a card that is already right — and the list row, if loaded,
  /// stops showing the old number.
  ///
  /// Returns null when it is done; otherwise why not ([ClientPhoneRefusal]):
  /// `invalid_phone` (the field's fault), `client_exists` (the other card's id
  /// and, read from that card, its name — null when it could not be read),
  /// `client_linked` (linked since it was opened: the card is read again, so
  /// it shows read-only), or any other refusal with its message.
  Future<ClientPhoneRefusal?> updatePhone(
    SalonId providerId,
    String clientId,
    String phone,
  ) async {
    final scope = _scope;
    try {
      final r = await _service.updatePhone(providerId, clientId, phone);
      if (scope != _scope) return null;
      final card = r.data?.card;
      if (r.success && card != null) {
        // The number HAS changed: a history that cannot be read now leaves
        // the visits as they were (the same bookings, moved) — never a
        // failure on a change that was made.
        List<Appointment>? visits;
        try {
          final v = await _service.getVisits(providerId, clientId);
          if (scope != _scope) return null;
          if (v.success) visits = v.data;
        } catch (_) {
          if (scope != _scope) return null;
          visits = null;
        }
        if (_cardProviderId == providerId && _cardClientId == clientId) {
          _cardRequest++; // an older quiet reload must not land over this
          _card = card;
          if (visits != null) _visits = visits;
        }
        final i = _clients.indexWhere((c) => c.id == clientId);
        if (i >= 0) {
          _clients[i] = _clients[i].copyWith(phone: card.client.phone);
        }
        notifyListeners();
        return null;
      }
      switch (r.code) {
        case 'client_exists':
          final takenBy = r.data?.takenBy;
          return ClientPhoneRefusal(
            code: r.code,
            message: r.error ?? 'Ce numéro est déjà sur une autre fiche.',
            takenById: takenBy,
            takenByName: takenBy == null
                ? null
                : await _nameOf(providerId, takenBy),
          );
        case 'client_linked':
          await _reloadCardQuietly();
        default:
          ProAccessGuard.report(r.code);
      }
      return ClientPhoneRefusal(
        code: r.code,
        message: r.error ?? 'Une erreur est survenue.',
      );
    } catch (_) {
      if (scope != _scope) return null;
      return const ClientPhoneRefusal(
        code: null,
        message: 'Une erreur est survenue.',
      );
    }
  }

  /// The name on another card of the salon — for « Ce numéro est déjà sur la
  /// fiche de {nom}. ». The 409 carries the card's id only; its `GET` (a read
  /// of that card, audited like any other) has the name. Null when it cannot
  /// be read: the sheet then says « d’un autre client ».
  Future<String?> _nameOf(SalonId providerId, String clientId) async {
    try {
      final r = await _service.getCard(providerId, clientId);
      final name = r.data?.client.displayName.trim();
      return r.success && name != null && name.isNotEmpty ? name : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> addNote(SalonId providerId, String clientId, String body) async {
    final scope = _scope;
    final r = await _service.addNote(
      providerId,
      clientId,
      body,
      idempotencyKey: _noteKey.forForm({
        'providerId': providerId,
        'clientId': clientId,
        'body': body,
      }),
    );
    if (scope != _scope) return false;
    if (r.success && r.data != null) _noteKey.settle();
    if (r.success && r.data != null && _card != null) {
      _card = _card!.copyWith(notes: [r.data!, ..._card!.notes]);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> deleteNote(
    SalonId providerId,
    String clientId,
    String noteId,
  ) async {
    final scope = _scope;
    final r = await _service.deleteNote(providerId, clientId, noteId);
    if (scope != _scope) return false;
    if (r.success && _card != null) {
      _card = _card!.copyWith(
        notes: _card!.notes.where((n) => n.id != noteId).toList(),
      );
      notifyListeners();
      return true;
    }
    return false;
  }

  /// R6 multi-salons: drop the previous salon's data on a switch.
  /// Which salon this state belongs to — moved by [resetForSalonSwitch]
  /// only. A read or a write takes it before it awaits and writes nothing
  /// when it moved meanwhile: its answer is the previous salon's, or the
  /// previous account's (docs/design/pro-account-scope.md §2.2).
  int _scope = 0;

  @override
  void resetForSalonSwitch() {
    _scope++;
    _cardRequest++; // a card reload in flight was for the previous salon
    _clients.clear();
    _total = 0;
    _availableTags = List.of(salonClientPresetTags);
    _query = '';
    _tag = '';
    _page = 1;
    _isLoading = false;
    _isLoadingMore = false;
    _error = null;
    _loadError = null;
    _lastAddWasDuplicate = false;
    _card = null;
    _visits = [];
    _cardLoading = false;
    _cardError = null;
    _cardErrorCode = null;
    _cardProviderId = null;
    _cardClientId = null;
    notifyListeners();
  }
}

/// Why [ProClientsProvider.updatePhone] did not change the number.
class ClientPhoneRefusal {
  const ClientPhoneRefusal({
    required this.code,
    required this.message,
    this.takenById,
    this.takenByName,
  });

  /// The server's code (`invalid_phone`, `client_exists`, `client_linked`,
  /// …), null for a failure that has none (offline).
  final String? code;

  /// The service's message, for a refusal the sheet has no words of its own
  /// for.
  final String message;

  /// `client_exists`: the card that already has the number, and its name
  /// when that card could be read.
  final String? takenById;
  final String? takenByName;
}
