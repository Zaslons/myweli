import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/salon_id.dart';
import '../../models/admin_salon_validation.dart';
import '../../models/salon_validation.dart';
import '../../services/admin/admin_response.dart';
import '../../services/admin/admin_service.dart';
import 'admin_salon_validation_count_provider.dart';
import 'admin_salon_validations_provider.dart';

/// One request of « Salons à valider », and the decision (B0.18 —
/// docs/design/salon-go-live-approval.md §4.3): the salon, its owner, the
/// history; « Valider la mise en ligne » (or « Validation à terminer ») and
/// « Refuser ».
///
/// **After a decision,** the queue's row leaves its tab at once, the
/// sidebar's count re-reads (§4.2), and the detail re-reads quietly so its
/// history is current. **After a failed one,** everything is re-read — the
/// detail, the queue, the count — because a validation can answer 409 AFTER
/// its decision was written (the going-live failed): the request may now read
/// « Validation à terminer ». Only the refusal's input errors (a 400 on the
/// note or the code) change nothing and re-read nothing.
class AdminSalonValidationDetailProvider extends ChangeNotifier {
  AdminSalonValidationDetailProvider({
    AdminService? service,
    this._queue,
    this._count,
  }) : _service = service ?? adminService;

  final AdminService _service;
  final AdminSalonValidationsProvider? _queue;
  final AdminSalonValidationCountProvider? _count;

  bool _isLoading = false;
  String? _error;
  String? _errorCode;
  bool _unavailable = false;
  SalonValidationDetail? _detail;
  String? _actionError;
  String? _actionCode;
  List<String> _actionMissing = const [];

  bool get isLoading => _isLoading;
  String? get error => _error;

  /// The load's failure code — `not_found` is a salon that does not exist
  /// (a link to a deleted salon, a mistyped id): a state of its own on the
  /// screen, where « Réessayer » could never succeed (SYSTEM §12).
  String? get errorCode => _errorCode;

  /// The server predates B0.18 — its route is absent (a calm state, §9.2).
  bool get unavailable => _unavailable;
  SalonValidationDetail? get detail => _detail;

  /// The salon whose decision is out, or null. One at a time: a second
  /// decision — on this request or another — waits for the first answer.
  SalonId? _actingOn;

  /// A decision on THIS request is out (the bar's buttons wait). A decision
  /// still out for a request the admin left does not busy this one's bar.
  bool get acting => _actingOn != null && _actingOn == _id;

  /// The last decision's failure, worded — shown in the sticky bar (a 409),
  /// or on the dialog's field ([actionCode] `note_required`/`note_too_long`).
  String? get actionError => _actionError;
  String? get actionCode => _actionCode;

  /// A 409 `incomplete`'s steps (`offer` among them for a lapsed offer).
  List<String> get actionMissing => _actionMissing;

  /// Whose detail this is. The provider is app-wide and outlives the screen,
  /// so without it the way to B showed A — A's photos, A's owner, and a
  /// « Valider » acting on B's id — until B answered (B9.8,
  /// docs/design/hygiene-batch9.md §14). The screen shows [detail] only when
  /// [id] is its own.
  SalonId? _id;
  SalonId? get id => _id;

  /// Bumped by every load: only the latest read writes.
  int _seq = 0;

  /// The refusal's input errors — a 400 on what the admin typed. Nothing
  /// changed on the server, so nothing is re-read.
  static const _inputErrors = {
    'invalid_input',
    'invalid_body',
    'note_required',
    'note_too_long',
  };

  Future<void> load(SalonId id) async {
    if (id != _id) {
      _id = id;
      _detail = null;
      _clearAction();
    }
    final seq = ++_seq;
    _isLoading = true;
    _error = null;
    _errorCode = null;
    _unavailable = false;
    notifyListeners();
    final res = await _service.salonValidationDetail(id);
    // Another read was asked for while this one was out: its answer is no
    // longer anybody's.
    if (seq != _seq || id != _id) return;
    _unavailable = res.routeMissing;
    if (res.success && res.data != null) {
      _detail = res.data;
    } else if (!res.routeMissing) {
      _error = res.error ?? 'Erreur lors du chargement';
      _errorCode = res.code;
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Re-reads the detail without the loading state — after a decision, under
  /// the bar's sentence. A failure keeps what is shown; a load started
  /// meanwhile wins.
  Future<void> _refresh(SalonId id) async {
    final seq = _seq;
    final res = await _service.salonValidationDetail(id);
    if (seq != _seq || id != _id) return;
    if (res.success && res.data != null) {
      _detail = res.data;
      notifyListeners();
    }
  }

  /// « Valider la mise en ligne », or « Validation à terminer »: sends the
  /// state this detail READ as `from` (§3.2). False without a request when
  /// there is nothing to validate here ([SalonValidationDetail.canApprove]),
  /// when [id] is not this detail's, or while a decision is out.
  Future<bool> approve(SalonId id) async {
    final d = _detail;
    final from = d?.approveFrom;
    if (_actingOn != null ||
        id != _id ||
        d == null ||
        from == null ||
        !d.canApprove) {
      return false;
    }
    return _decide(
      id,
      _service.approveSalonValidation(id, from: from),
      (approval) => (approval.validation, approval.salonStatus),
    );
  }

  /// « Refuser » with a code from §4.3's list and, for `other`, a note
  /// (≤ 500 code points, counted as the server counts them). An input the
  /// server would refuse is refused here first, on the field, with the
  /// server's own code and sentence — the server still checks it again.
  Future<bool> refuse(SalonId id, {required String code, String? note}) async {
    final d = _detail;
    if (_actingOn != null || id != _id || d == null || !d.canRefuse) {
      return false;
    }
    final invalid = refusalInputError(code: code, note: note ?? '');
    if (invalid != null) {
      _actionCode = invalid;
      _actionError = AdminService.sentenceFor(invalid);
      _actionMissing = const [];
      notifyListeners();
      return false;
    }
    return _decide(
      id,
      _service.refuseSalonValidation(id, code: code, note: note),
      (validation) => (validation, null),
    );
  }

  Future<bool> _decide<T extends Object>(
    SalonId id,
    Future<AdminResponse<T>> call,
    (SalonValidation?, String?) Function(T data) outcome,
  ) async {
    _actingOn = id;
    _clearAction();
    notifyListeners();
    try {
      final res = await call;
      final data = res.data;
      if (res.success && data != null) {
        final (validation, salonStatus) = outcome(data);
        if (id == _id && _detail != null) {
          _detail = _detail!.decided(validation, salonStatus: salonStatus);
        }
        _queue?.applyDecision(id, validation);
        unawaited(_count?.load());
        unawaited(_refresh(id));
        return true;
      }
      if (id == _id) {
        _actionCode = res.code;
        _actionError = res.error ?? 'Action impossible';
        _actionMissing = res.missing;
      }
      if (!_inputErrors.contains(res.code)) {
        unawaited(_refresh(id));
        unawaited(_queue?.load());
        unawaited(_count?.load());
      }
      return false;
    } finally {
      _actingOn = null;
      notifyListeners();
    }
  }

  /// The bar's sentence was read, or the dialog reopened.
  void clearActionError() {
    if (_actionError == null) return;
    _clearAction();
    notifyListeners();
  }

  void _clearAction() {
    _actionError = null;
    _actionCode = null;
    _actionMissing = const [];
  }
}
