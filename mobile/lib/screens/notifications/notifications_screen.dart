import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../widgets/common/consumer_bottom_nav.dart';
import '../../widgets/notifications/mark_all_read_button.dart';
import '../../widgets/notifications/notifications_list.dart';

/// The consumer notification centre. The feed itself is [NotificationsList],
/// and « Tout marquer comme lu » is [MarkAllReadButton] — both shared with the
/// pro app, which wraps them in its own chrome.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: const [MarkAllReadButton()],
      ),
      body: const NotificationsList(),
      bottomNavigationBar: const ConsumerBottomNav(current: ConsumerTab.actu),
    );
  }
}
