import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/open_sign_in.dart';
import '../../core/constants/failure_messages.dart';
import '../../core/utils/salon_id.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../common/app_snack_bar.dart';

/// A heart tapped by a guest (consumer-signin-push.md §2.8, decision 205):
/// the sign-in opens over the screen the person is on; once they are back,
/// signed in, the salon is added — unless it already is a favourite, which a
/// toggle would have removed.
///
/// Everything it needs is captured BEFORE the sign-in opens, by the caller:
/// the tap's own `userId` and `isFavorite` were the guest's (`''` and
/// `false`), and a card may be rebuilt or unmounted while its list reloads
/// for the new account (§2.3). The account is read only AFTER the sign-in.
Future<void> heartAfterSignIn({
  required GoRouter router,
  required ScaffoldMessengerState messenger,
  required AuthProvider auth,
  required FavoritesProvider favorites,
  required SalonId salonId,
}) async {
  final signedIn = await openSignIn(router, reason: SignInReason.heart);
  final userId = auth.user?.id;
  if (!signedIn || userId == null) return;
  switch (await favorites.addIfMissing(userId, salonId)) {
    case FavoriteAddOutcome.added:
      AppSnackBar.showOn(
        messenger,
        'Ajouté aux favoris',
        kind: SnackKind.success,
        action: SnackAction(
          label: 'Annuler',
          onPressed: () => favorites.toggleFavorite(userId, salonId),
          // §15 as amended by A6: the heart itself is a one-tap undo.
          isOnlyRouteBack: false,
        ),
      );
    case FavoriteAddOutcome.alreadyThere:
      AppSnackBar.showOn(messenger, 'Déjà dans vos favoris');
    case FavoriteAddOutcome.failed:
      AppSnackBar.showOn(
        messenger,
        favorites.error ?? kGenericErrorMessage,
        kind: SnackKind.error,
      );
  }
}
