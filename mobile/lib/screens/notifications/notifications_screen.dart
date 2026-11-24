import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/open_sign_in.dart';
import '../../core/theme/colors.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/consumer_bottom_nav.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/screen_title.dart';
import '../../widgets/notifications/mark_all_read_button.dart';
import '../../widgets/notifications/notifications_list.dart';

/// The consumer notification centre. The feed itself is [NotificationsList],
/// and « Tout marquer comme lu » is [MarkAllReadButton] — both shared with the
/// pro app, which wraps them in its own chrome.
///
/// A guest reads a signed-out page instead of the feed
/// (consumer-signin-push.md §2.5, decision 207): the feed's service answers
/// « Non connecté » without asking the server, and the screen showed a load
/// error whose « Réessayer » could never succeed (SYSTEM §12).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Watched: a sign-in, or a session that ends here, redraws the page; the
    // feed, mounted afresh, loads itself.
    final guest = !context.watch<AuthProvider>().isAuthenticated;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const ScreenTitle('Notifications'),
        // It would act on nothing for a guest.
        actions: guest ? null : const [MarkAllReadButton()],
      ),
      body: guest
          ? EmptyState(
              icon: Icons.notifications_none,
              title: 'Vos notifications',
              description:
                  'Connectez-vous pour suivre vos rendez-vous et les réponses '
                  'des salons.',
              actionText: 'Se connecter',
              onAction: () =>
                  openSignIn(GoRouter.of(context), reason: SignInReason.actu),
            )
          : const NotificationsList(),
      bottomNavigationBar: const ConsumerBottomNav(current: ConsumerTab.actu),
    );
  }
}
