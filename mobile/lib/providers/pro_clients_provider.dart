import 'package:flutter/foundation.dart';

import '../core/access/pro_access_guard.dart';
import '../core/di/dependency_injection.dart';
import '../models/appointment.dart';
import '../models/salon_client.dart';
import '../services/interfaces/pro_clients_service_interface.dart';

/// State for the salon client base (module `clients` C1 —
/// docs/design/clients-c1.md §5): the list (search / tag filter / infinite
/// scroll) and the open card (stats, notes, visits).
class ProClientsProvider extends ChangeNotifier {
  final ProClientsServiceInterface _service = serviceLocator.proClientsService;

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

  /// True when the salon simply has no clients yet (vs an empty search).
  bool get isBaseEmpty => _total == 0 && _query.isEmpty && _tag.isEmpty;

  Future<void> load(String providerId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final r = await _service.listClients(
        providerId,
        query: _query.isEmpty ? null : _query,
        tag: _tag.isEmpty ? null : _tag,
      );
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
        _error = r.error ?? 'Une erreur est survenue.';
        ProAccessGuard.report(r.code);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore(String providerId) async {
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
      if (r.success && r.data != null) {
        _clients.addAll(r.data!.items);
        _total = r.data!.total;
        _page += 1;
      }
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> search(String providerId, String query) {
    _query = query.trim();
    return load(providerId);
  }

  /// Toggles [tag] (tapping the active chip clears the filter).
  Future<void> filterByTag(String providerId, String tag) {
    _tag = _tag == tag ? '' : tag;
    return load(providerId);
  }

  /// Returns the new/existing client id, or null on failure. On a duplicate
  /// phone the id of the EXISTING card comes back and [lastAddWasDuplicate]
  /// is set (UI: toast « Ce numéro existe déjà » + open the card).
  bool _lastAddWasDuplicate = false;
  bool get lastAddWasDuplicate => _lastAddWasDuplicate;

  Future<String?> addClient(
    String providerId, {
    required String name,
    required String phone,
    String? note,
  }) async {
    _error = null;
    _lastAddWasDuplicate = false;
    final r = await _service.addClient(
      providerId,
      name: name,
      phone: phone,
      note: note,
    );
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

  Future<void> loadCard(String providerId, String clientId) async {
    _cardLoading = true;
    _cardError = null;
    _card = null;
    _visits = [];
    notifyListeners();
    try {
      final r = await _service.getCard(providerId, clientId);
      if (r.success && r.data != null) {
        _card = r.data;
        final v = await _service.getVisits(providerId, clientId);
        _visits = v.data ?? [];
      } else {
        _cardError = r.error ?? 'Une erreur est survenue.';
        _cardErrorCode = r.code;
      }
    } catch (e) {
      _cardError = e.toString();
    } finally {
      _cardLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateTags(
    String providerId,
    String clientId,
    List<String> tags,
  ) async {
    final r = await _service.updateTags(providerId, clientId, tags);
    if (r.success && r.data != null && _card != null) {
      _card = _card!.copyWith(client: r.data);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> addNote(
    String providerId,
    String clientId,
    String body,
  ) async {
    final r = await _service.addNote(providerId, clientId, body);
    if (r.success && r.data != null && _card != null) {
      _card = _card!.copyWith(notes: [r.data!, ..._card!.notes]);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> deleteNote(
    String providerId,
    String clientId,
    String noteId,
  ) async {
    final r = await _service.deleteNote(providerId, clientId, noteId);
    if (r.success && _card != null) {
      _card = _card!.copyWith(
        notes: _card!.notes.where((n) => n.id != noteId).toList(),
      );
      notifyListeners();
      return true;
    }
    return false;
  }
}
