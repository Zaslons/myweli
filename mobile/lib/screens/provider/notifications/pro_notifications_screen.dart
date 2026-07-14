import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../providers/notifications_provider.dart';
import '../../../widgets/notifications/notifications_list.dart';

/// The salon's notification centre — what the dashboard bell finally opens.
///
/// Fed by the provider-directed events the backend writes for every team
/// member (new booking · client cancellation · deposit proof —
/// docs/design/push-notifications-fcm.md §10). A row's route carries its
/// `?salon=`, so tapping one from a multi-salon account switches to the right
/// salon before opening the booking.
///
/// The list itself is the shared [NotificationsList]; only the chrome differs
/// from the consumer centre (no bottom nav).
class ProNotificationsScreen extends StatelessWidget {
  const ProNotificationsScreen({super.key});

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
              return TextButton(
                onPressed: provider.markAllRead,
                child: Text(
                  'Tout lire',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: const NotificationsList(
        emptyTitle: 'Aucune notification',
        emptyDescription:
            'Les réservations, annulations et acomptes de vos clients '
            'apparaîtront ici.',
      ),
    );
  }
}
