import 'package:flutter/foundation.dart';

import '../../services/admin/admin_service.dart';
import 'admin_auth_provider.dart';

/// The sidebar's « Salons à valider » count (B0.18 —
/// docs/design/salon-go-live-approval.md §4.1): the « En attente » tab's
/// `total`, read with one row.
///
/// **Silent by design.** [count] is null — no badge — when the server
/// predates B0.18 (its route answers 404: the console goes live first, §9.2),
/// on any error, and while signed out. It has no error state and never
/// raises one: a badge is a hint, and the queue screen says what is wrong.
/// The sidebar reads it with `context.watch<AdminSalonValidationCountProvider?>()`,
/// so a screen pumped without it shows no badge either.
///
/// **When it loads:** at sign-in — a stored session restored or a login, both
/// seen through [AdminAuthProvider] — and after every decision that moves a
/// request in or out of « En attente » (validate, refuse, suspend, lift), by
/// the providers that take them.
class AdminSalonValidationCountProvider extends ChangeNotifier {
  AdminSalonValidationCountProvider({
    AdminService? service,
    AdminAuthProvider? auth,
  }) : _service = service ?? adminService,
       _auth = auth {
    auth?.addListener(_onAuth);
    _onAuth();
  }

  final AdminService _service;
  final AdminAuthProvider? _auth;

  bool _signedIn = false;
  int? _count;

  /// Pending requests, or null: no badge.
  int? get count => _count;

  /// Bumped by every load and every sign-out, so a late answer never writes
  /// over a newer one — or over a signed-out console.
  int _seq = 0;

  void _onAuth() {
    final auth = _auth;
    if (auth == null) return;
    final signedIn = auth.isAuthenticated;
    if (signedIn == _signedIn) return;
    _signedIn = signedIn;
    if (signedIn) {
      load();
    } else {
      _seq++;
      _set(null);
    }
  }

  /// Re-reads the count. Without an [AdminAuthProvider] (a test, a screen
  /// pumped alone) it always reads; with one, only while signed in.
  Future<void> load() async {
    if (_auth != null && !_signedIn) return;
    final seq = ++_seq;
    final res = await _service.pendingSalonValidationCount();
    if (seq != _seq) return;
    _set(res.success ? res.data : null);
  }

  void _set(int? next) {
    if (next == _count) return;
    _count = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _seq++; // an answer still out is nobody's
    _auth?.removeListener(_onAuth);
    super.dispose();
  }
}
