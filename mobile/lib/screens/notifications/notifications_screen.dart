import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/notifications_provider.dart';
import '../../widgets/notifications/notifications_list.dart';

/// The consumer notification centre. The feed itself is [NotificationsList] —
/// shared with the pro app, which wraps it in its own chrome.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          Consumer<NotificationsProvider>(
            builder: (context, provider, _) {
              if (provider.unreadCount == 0) return const SizedBox.shrink();
              // A15 (§21 row 79) — an icon, not a label. An action's text is
              // scaled by the FULL system scaler while the title is clamped to
              // 1.34× (`app_bar.dart:1092`), so a `TextButton` here costs
              // ~137dp at 2× and leaves the title under 176. Measured in
              // `primitives_test.dart`: with a text action, « Avis » — four
              // characters — cannot fit. The tooltip is also free to be
              // CLEARER than the label was, because it has the whole screen.
              return IconButton(
                onPressed: provider.markAllRead,
                icon: const Icon(Icons.done_all),
                tooltip: 'Tout marquer comme lu',
              );
            },
          ),
        ],
      ),
      body: const NotificationsList(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 3,
        onTap: (index) {
          if (index == 0) context.go('/home');
          if (index == 1) context.push('/favorites');
          if (index == 2) context.push('/bookings');
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Accueil'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Carte'),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Rendez-vous',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_none),
            label: 'Actu',
          ),
        ],
        selectedLabelStyle: AppTextStyles.labelSmall,
        unselectedLabelStyle: AppTextStyles.labelSmall,
      ),
    );
  }
}
