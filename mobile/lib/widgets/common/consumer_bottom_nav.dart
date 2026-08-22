import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The consumer app's bottom tab strip — **one declaration, four screens**.
///
/// It was copied into `home`, `map`, `my_bookings` and `notifications`, and the
/// copies had already drifted: `notifications_screen` re-declared
/// `selectedLabelStyle`/`unselectedLabelStyle` that `AppTheme`'s
/// `bottomNavigationBarTheme` already supplies, and a fifth copy lived in
/// `favorites_screen.dart` — a screen registered on no route, reachable from
/// nowhere — declaring a DIFFERENT set (`Favoris`, `Profil`). That dead copy is
/// why the strip appeared to change meaning between screens.
///
/// **« Carte » routes to the favourites map, and that is correct.** PRD
/// FR-FAV-001 is *"add/remove favorites; favorites map view; deep-link focus"*,
/// and `MapScreen` is that view: it loads `FavoritesProvider`, draws a heart on
/// every marker, toggles from the pin, and titles itself « Carte ». The home
/// screen's own « Mes favoris » section says « Voir la carte » for the same
/// reason. The route was named `/favorites` while building `MapScreen`, which
/// read as a routing bug to everyone who met it — it is `/carte` now, and the
/// test beside this widget asserts label and destination *together* so the pair
/// cannot drift apart again.
enum ConsumerTab {
  accueil(Icons.home, 'Accueil', '/home'),
  carte(Icons.map, 'Carte', '/carte'),
  rendezVous(Icons.calendar_today, 'Rendez-vous', '/bookings'),
  actu(Icons.notifications_none, 'Actu', '/notifications');

  const ConsumerTab(this.icon, this.label, this.route);

  final IconData icon;
  final String label;
  final String route;
}

class ConsumerBottomNav extends StatelessWidget {
  const ConsumerBottomNav({super.key, required this.current});

  /// The tab whose screen is showing. Tapping it is a no-op — pushing the
  /// route you are already on stacks a second copy and gives the back button
  /// somewhere pointless to go.
  final ConsumerTab current;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: current.index,
      // Styling comes from `AppTheme.bottomNavigationBarTheme` — colours, type,
      // elevation and both label styles. Restating any of it here is how the
      // copies diverged in the first place.
      onTap: (index) {
        final target = ConsumerTab.values[index];
        if (target == current) return;
        // Home is the stack's root: `go` replaces rather than piling `/home`
        // on top of itself. Every other tab pushes, so back returns to where
        // the user came from. This is what the four copies already did.
        if (target == ConsumerTab.accueil) {
          context.go(target.route);
        } else {
          context.push(target.route);
        }
      },
      items: [
        for (final tab in ConsumerTab.values)
          BottomNavigationBarItem(icon: Icon(tab.icon), label: tab.label),
      ],
    );
  }
}
