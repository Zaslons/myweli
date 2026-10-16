import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/pro_router.dart';
import '../../core/theme/colors.dart';
import '../../providers/pro_auth_provider.dart';
import '../common/empty_state.dart';
import '../common/loading_indicator.dart';

/// No Pro page renders on a salon the app does not know
/// (docs/design/pro-app-salon-not-loaded.md §3.2, §4).
///
/// Every Pro time is the SALON's time, and the salon's timezone arrives with
/// GET /me/provider — or, at cold start, from the session that kept the last
/// answer. When neither has it (a sign-in whose /me failed, the first start
/// after the update with /me failing, an R6 fallback whose refetch failed),
/// `salon_time.dart` would quietly answer Africa/Abidjan, and the journal's
/// « Reprogrammer » would send an instant an hour off for a salon in
/// Libreville. This stands in for every page instead, once, above the router
/// (`main_pro.dart`'s `MaterialApp.router` builder) — a tapped notification
/// opening `/pro/appointment/:id` is covered like the dashboard.
///
/// **It REPLACES the router's subtree; it does not cover it.** Covered pages
/// would still be built, and would start their loads on the guessed clock —
/// the journal anchors its « aujourd'hui » on its first load. Replaced, they
/// are built when the salon is known; go_router rebuilds the same page stack
/// from its own state when the `Router` comes back.
///
/// The location is read from the router's `routeInformationProvider`, not
/// its delegate's configuration: with the `Router` off the tree the delegate
/// stops hearing about navigation, the provider does not.
class ProSalonGate extends StatefulWidget {
  const ProSalonGate({super.key, required this.router, required this.child});

  /// Where the gate stands aside: the launch screens (the splash plays,
  /// sign-in signs in) and the rejoin gate's « Invitations », whose session
  /// holds no salon on purpose.
  static const exemptPaths = {...ProRouter.launchPaths, '/pro/invitations'};

  final GoRouter router;
  final Widget child;

  @override
  State<ProSalonGate> createState() => _ProSalonGateState();
}

class _ProSalonGateState extends State<ProSalonGate> {
  @override
  void initState() {
    super.initState();
    widget.router.routeInformationProvider.addListener(_moved);
  }

  @override
  void didUpdateWidget(covariant ProSalonGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routeInformationProvider.removeListener(_moved);
      widget.router.routeInformationProvider.addListener(_moved);
    }
  }

  @override
  void dispose() {
    widget.router.routeInformationProvider.removeListener(_moved);
    super.dispose();
  }

  void _moved() {
    if (!mounted) return;
    // The router can report a location while a frame is being built.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _signOut() async {
    await context.read<ProAuthProvider>().logout();
    widget.router.go('/pro/login');
  }

  @override
  Widget build(BuildContext context) {
    // Not read yet is not signed out: a page built now would read no salon
    // and a signed-out clock. Whether the screen shows the wait or the
    // message is its own business ([ProAuthProvider.salonLoading]).
    final closed = context.select<ProAuthProvider, bool>(
      (auth) => !auth.sessionRestored || auth.needsSalon,
    );
    final path = widget.router.routeInformationProvider.value.uri.path;
    if (!closed || ProSalonGate.exemptPaths.contains(path)) {
      return widget.child;
    }
    // Its own Navigator: the router's is off the tree, and the bar's tooltip
    // needs an Overlay.
    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => ProSalonUnavailableScreen(onSignOut: _signOut),
      ),
    );
  }
}

/// « Impossible de charger votre salon » — what stands in for the Pro pages
/// while the salon is unknown (pro-app-salon-not-loaded.md §4). Retrying is
/// the way out when the network is the problem; « Déconnexion » when the
/// server will keep refusing (SYSTEM.md §12).
class ProSalonUnavailableScreen extends StatelessWidget {
  const ProSalonUnavailableScreen({super.key, required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProAuthProvider>();
    final waiting = auth.salonLoading;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        // Nowhere to go back to — only out. No title: the salon's name is
        // real data with no width budget in a bar (§13.3); the message says
        // « votre salon ».
        automaticallyImplyLeading: false,
        actions: [
          // An icon, as on the rejoin gate: a text action crowds the bar at
          // 200 %. Held while an answer is out — a sign-out under a refresh
          // would have the refresh land on a signed-out session.
          IconButton(
            onPressed: waiting ? null : onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Déconnexion',
          ),
        ],
      ),
      body: waiting
          ? const LoadingIndicator()
          : EmptyState(
              icon: Icons.wifi_off,
              title: 'Impossible de charger votre salon',
              description:
                  'Les heures de vos rendez-vous en dépendent. Vérifiez '
                  'votre connexion, puis réessayez.',
              actionText: 'Réessayer',
              onAction: auth.retrySalon,
            ),
    );
  }
}
