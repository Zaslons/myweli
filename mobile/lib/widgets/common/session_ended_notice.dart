import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/open_sign_in.dart';
import '../../providers/auth_provider.dart';
import 'app_snack_bar.dart';

/// What the person reads when the server ended the session — what happened,
/// then what to do (SYSTEM.md §17). « Expiré » is the usual case; a session
/// revoked, or an account deleted elsewhere, gets it too: the person has one
/// thing to do either way. docs/design/consumer-account-scope.md §7.
const String kSessionEndedMessage = 'Votre session a expiré. Reconnectez-vous.';

/// The screens that only exist for a signed-in account: on one of them, a
/// session that ended opens the sign-in OVER the screen, and success comes
/// back to it (consumer-signin-push.md §2.7, decision 213). Prefixes of the
/// consumer router's paths (`app_router.dart`).
///
/// **Not here: the screens that draw their own signed-out state** — Profil,
/// Modifier le profil, « Rendez-vous » and « Actu » (§2.5). There the notice
/// only says so, with « Se connecter ».
const List<String> kAccountOnlyRoutePrefixes = [
  '/appointment/',
  '/booking/confirm',
  '/profile/notifications',
  '/profile/data',
];

bool isAccountOnlyRoute(String location) =>
    kAccountOnlyRoutePrefixes.any(location.startsWith);

/// The way out of an account the person did not choose (§2.5, Q1 = a): the
/// session the server refused ends where the person is. On a screen that can
/// show itself signed out, a snackbar says it and offers « Se connecter »; on
/// an account screen, the sign-in opens over it and comes back to it
/// (consumer-signin-push.md §2.7, decision 213).
///
/// One listener at the app's root (`MaterialApp.builder`, under its
/// `ScaffoldMessenger`), rather than one per screen. [router] is passed in:
/// the builder sits ABOVE the Router, where `GoRouter.of` finds nothing.
class SessionEndedNotice extends StatefulWidget {
  const SessionEndedNotice({
    super.key,
    required this.router,
    required this.child,
  });

  final GoRouter router;
  final Widget child;

  @override
  State<SessionEndedNotice> createState() => _SessionEndedNoticeState();
}

class _SessionEndedNoticeState extends State<SessionEndedNotice> {
  AuthProvider? _auth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (identical(auth, _auth)) return;
    _auth?.removeListener(_onAuth);
    _auth = auth..addListener(_onAuth);
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuth);
    super.dispose();
  }

  /// Where the person is: the stack's LAST route, opened with `go` or with
  /// `push`. The configuration's own address (`currentConfiguration.uri`)
  /// ignores every pushed route (go_router 17.5, `match.dart:530-533`) — and
  /// every account screen is pushed, so the notice used to believe the person
  /// was on Accueil (consumer-signin-push.md §2.7).
  String _here() => widget.router.state.uri.toString();

  void _onAuth() {
    if (!(_auth?.consumeSessionEndedNotice() ?? false)) return;
    final here = _here();
    // The sign-in is already the way back.
    if (here.startsWith('/login')) return;
    if (isAccountOnlyRoute(here)) {
      // Its reason line says « Votre session a expiré. Reconnectez-vous. ».
      unawaited(_signInOverAccountScreen());
      return;
    }
    AppSnackBar.showOn(
      ScaffoldMessenger.of(context),
      kSessionEndedMessage,
      action: SnackAction(
        label: 'Se connecter',
        onPressed: () =>
            openSignIn(widget.router, reason: SignInReason.sessionEnded),
        // The screen's own « Se connecter » is another way there.
        isOnlyRouteBack: false,
      ),
    );
  }

  /// The sign-in opens over the account screen (decision 213, refining
  /// Q1 = a: the session ends where the person is, and comes back there).
  /// Signed in: the screen loads again by itself (`ReloadOnSignIn`).
  /// « Fermer »: back to the nearest screen that can show itself signed out,
  /// Accueil if there is none — from the confirmation, that is the hub.
  Future<void> _signInOverAccountScreen() async {
    final router = widget.router;
    final signedIn = await openSignIn(
      router,
      reason: SignInReason.sessionEnded,
    );
    if (signedIn) return;
    // A route without `onExit` leaves go_router's stack as it pops
    // (`delegate.dart` `_handlePopPageWithRouteMatch`), so the top read after
    // each pop is the new one. Bounded: a stack is a handful of screens.
    for (var i = 0; i < 8 && isAccountOnlyRoute(_here()); i++) {
      if (!router.canPop()) break;
      router.pop();
    }
    if (isAccountOnlyRoute(_here())) router.go('/home');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
