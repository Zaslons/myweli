import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

/// A screen that reads one record of the account loads it again when someone
/// signs in while it is open (consumer-signin-push.md §2.3). Since A3 the
/// sign-in opens OVER the screen the person is on and returns to it — the
/// screen is not built again, as it was when the sign-in replaced it.
///
/// It reacts to [AuthProvider.signInSerial], which moves once per sign-in made
/// in the app — never for the session restored at launch, which the screen's
/// own `initState` already loads.
mixin ReloadOnSignIn<T extends StatefulWidget> on State<T> {
  AuthProvider? _signInSource;
  int _seenSignIn = 0;

  /// Someone signed in while this screen was open: load its record again.
  void reloadForSignIn();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (identical(auth, _signInSource)) return;
    _signInSource?.removeListener(_onAuthChanged);
    _signInSource = auth..addListener(_onAuthChanged);
    _seenSignIn = auth.signInSerial;
  }

  void _onAuthChanged() {
    final auth = _signInSource;
    if (auth == null || auth.signInSerial == _seenSignIn) return;
    _seenSignIn = auth.signInSerial;
    if (mounted && auth.isAuthenticated) reloadForSignIn();
  }

  @override
  void dispose() {
    _signInSource?.removeListener(_onAuthChanged);
    _signInSource = null;
    super.dispose();
  }
}
