import 'package:flutter/foundation.dart';

import '../../core/utils/salon_id.dart';
import '../../models/admin_salon_validation.dart';
import '../../models/salon_validation.dart';
import '../../services/admin/admin_service.dart';

/// « Salons à valider » — the queue (B0.18,
/// docs/design/salon-go-live-approval.md §4.2): three tabs, « En attente »
/// (oldest request first) · « Refusés » · « Validés », [pageSize] per page
/// with previous/next (the audit log's pattern).
///
/// **Before the backend deploy** (§9.2) the route answers 404: [unavailable]
/// is then true and [error] null — the screen shows a calm, explicit state,
/// never an error.
class AdminSalonValidationsProvider extends ChangeNotifier {
  AdminSalonValidationsProvider({AdminService? service})
    : _service = service ?? adminService;

  final AdminService _service;

  static const pageSize = 50;

  /// The tabs, in the order the console shows them.
  static const tabs = [
    SalonValidationState.pending,
    SalonValidationState.refused,
    SalonValidationState.approved,
  ];

  bool _isLoading = false;
  String? _error;
  bool _unavailable = false;
  List<SalonValidationQueueItem> _items = const [];
  int _page = 1;
  int _total = 0;
  SalonValidationState _tab = SalonValidationState.pending;

  bool get isLoading => _isLoading;
  String? get error => _error;

  /// The server predates B0.18 — its route is absent.
  bool get unavailable => _unavailable;
  List<SalonValidationQueueItem> get items => _items;
  int get page => _page;
  int get total => _total;
  SalonValidationState get tab => _tab;
  bool get hasPrev => _page > 1;
  bool get hasNext => _page * pageSize < _total;

  /// Bumped by every load: a tab or a page asked for while a read was out
  /// makes that read's answer nobody's — « Refusés » never lands under
  /// « En attente ».
  int _seq = 0;

  Future<void> load() async {
    final seq = ++_seq;
    final tab = _tab;
    final page = _page;
    _isLoading = true;
    _error = null;
    notifyListeners();
    final res = await _service.salonValidationQueue(
      state: tab,
      page: page,
      pageSize: pageSize,
    );
    if (seq != _seq) return;
    _unavailable = res.routeMissing;
    if (res.success && res.data != null) {
      _items = res.data!.items;
      _total = res.data!.total;
    } else {
      _items = const [];
      _total = 0;
      _error = res.routeMissing
          ? null
          : (res.error ?? 'Erreur lors du chargement');
    }
    _isLoading = false;
    notifyListeners();
  }

  void setTab(SalonValidationState tab) {
    assert(tabs.contains(tab), 'not a tab');
    if (_tab == tab) return;
    _tab = tab;
    _page = 1;
    _items = const [];
    _total = 0;
    load();
  }

  void nextPage() {
    if (!hasNext) return;
    _page++;
    load();
  }

  void prevPage() {
    if (!hasPrev) return;
    _page--;
    load();
  }

  /// A decision answered for [id] (§4.2: « the row leaves the tab at
  /// once »). [now] is the validation it returned: a row whose state still
  /// belongs to this tab stays, updated — « Validation à terminer » finished
  /// under « Validés » is still validated — and any other leaves, with the
  /// total. Nothing to do when the row is not on this page.
  ///
  /// A page emptied this way past the first steps back one page, so the tab
  /// never reads « Aucun salon » while earlier pages hold some.
  void applyDecision(SalonId id, SalonValidation? now) {
    final i = _items.indexWhere((r) => r.providerId == id);
    if (i < 0) return;
    if (now != null && now.state == _tab) {
      _items = List.unmodifiable([
        for (final r in _items) r.providerId == id ? r.withValidation(now) : r,
      ]);
      notifyListeners();
      return;
    }
    _items = List.unmodifiable([
      for (final r in _items)
        if (r.providerId != id) r,
    ]);
    _total = _total > 0 ? _total - 1 : 0;
    if (_items.isEmpty && _page > 1) {
      _page--;
      load();
      return;
    }
    notifyListeners();
  }
}
