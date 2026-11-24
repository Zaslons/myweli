import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../providers/appointment_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';

/// The account's lists load once, for the whole app, when someone signs in
/// (consumer-signin-push.md §2.3) — the other half of `AccountScope`, which
/// empties them when the account changes.
///
/// **Why it exists.** Accueil, the salon page and the map load the favourites
/// and the bookings once, when they open, and only if someone is signed in
/// then. While the sign-in REPLACED the screen (`go`), every screen was built
/// again and loaded; since A3 it opens over the screen and returns to it, so
/// nothing would. An empty heart on a salon already in the favourites,
/// tapped, would then have removed it.
///
/// It listens to [AuthProvider.signInSerial]: a sign-in made in the app, never
/// the session restored at launch (each screen's `initState` loads that).
class AccountLoader extends StatefulWidget {
  const AccountLoader({super.key, required this.child});

  final Widget child;

  @override
  State<AccountLoader> createState() => _AccountLoaderState();
}

class _AccountLoaderState extends State<AccountLoader> {
  AuthProvider? _auth;
  int _seenSignIn = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (identical(auth, _auth)) return;
    _auth?.removeListener(_onAuth);
    _auth = auth..addListener(_onAuth);
    _seenSignIn = auth.signInSerial;
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    final auth = _auth;
    if (auth == null || auth.signInSerial == _seenSignIn) return;
    _seenSignIn = auth.signInSerial;
    final user = auth.user;
    if (!mounted || user == null) return;
    unawaited(
      context.read<FavoritesProvider>().loadFavorites(user.id, force: true),
    );
    unawaited(context.read<AppointmentProvider>().loadAppointments());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
