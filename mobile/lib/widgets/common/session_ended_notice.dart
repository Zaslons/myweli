import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'app_snack_bar.dart';

/// What the person reads when the server ended the session — what happened,
/// then what to do (SYSTEM.md §17). « Expiré » is the usual case; a session
/// revoked, or an account deleted elsewhere, gets it too: the person has one
/// thing to do either way. docs/design/consumer-account-scope.md §7.
const String kSessionEndedMessage = 'Votre session a expiré. Reconnectez-vous.';

/// The screens that only exist for a signed-in account: on one of them, a
/// session that ended takes the person to the sign-in — and back here after
/// it (`returnTo`), as « Mes rendez-vous » already does for a guest. Prefixes
/// of the consumer router's paths (`app_router.dart`); `/profile` itself is
/// not one — it draws its guest state.
const List<String> kAccountOnlyRoutePrefixes = [
  '/bookings',
  '/appointment/',
  '/notifications',
  '/profile/',
  '/booking/confirm',
];

bool isAccountOnlyRoute(String location) =>
    kAccountOnlyRoutePrefixes.any(location.startsWith);

/// The way out of an account the person did not choose (§2.5, Q1 = a): the
/// session the server refused ends where the person is. One snackbar says
/// it; on a public screen it offers « Se connecter », and an account screen
/// leaves for the sign-in instead.
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

  void _onAuth() {
    if (!(_auth?.consumeSessionEndedNotice() ?? false)) return;
    final here = widget.router.routerDelegate.currentConfiguration.uri
        .toString();
    final signIn = '/login?returnTo=${Uri.encodeComponent(here)}';
    final messenger = ScaffoldMessenger.of(context);
    if (isAccountOnlyRoute(here)) {
      AppSnackBar.showOn(messenger, kSessionEndedMessage);
      widget.router.go(signIn);
      return;
    }
    AppSnackBar.showOn(
      messenger,
      kSessionEndedMessage,
      action: SnackAction(
        label: 'Se connecter',
        onPressed: () => widget.router.go(signIn),
        // The Profile's « Se connecter » is another way there.
        isOnlyRouteBack: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
