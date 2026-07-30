import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/push/system_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../providers/notifications_provider.dart';
import '../../../services/interfaces/push_notification_service_interface.dart';
import '../../../widgets/notifications/notifications_list.dart';
import '../../../widgets/push/push_blocked_banner.dart';

/// The salon's notification centre — what the dashboard bell finally opens.
///
/// Fed by the provider-directed events the backend writes for every team
/// member (new booking · client cancellation · deposit proof —
/// docs/design/push-notifications-fcm.md §10). A row's route carries its
/// `?salon=`, so tapping one from a multi-salon account switches to the right
/// salon before opening the booking.
///
/// The list itself is the shared [NotificationsList]; only the chrome differs
/// from the consumer centre (no bottom nav). The pro app has no preferences
/// screen, so this is also where a salon learns that its phone is blocking
/// notifications — and how to fix it.
class ProNotificationsScreen extends StatefulWidget {
  const ProNotificationsScreen({
    super.key,
    this.openSettings = openSystemNotificationSettings,
    this.permissionStatus,
  });

  /// Test seams.
  final SettingsOpener openSettings;
  final Future<PushPermissionStatus> Function()? permissionStatus;

  @override
  State<ProNotificationsScreen> createState() => _ProNotificationsScreenState();
}

class _ProNotificationsScreenState extends State<ProNotificationsScreen>
    with WidgetsBindingObserver {
  bool _osDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshOsPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshOsPermission();
  }

  Future<void> _refreshOsPermission() async {
    final read = widget.permissionStatus ??
        serviceLocator.pushNotificationService.permissionStatus;
    final status = await read();
    if (!mounted) return;
    setState(() => _osDenied = status == PushPermissionStatus.denied);
  }

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
      body: Column(
        children: [
          if (_osDenied)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingM,
                AppTheme.spacingM,
                AppTheme.spacingM,
                0,
              ),
              child: PushBlockedBanner(onOpenSettings: widget.openSettings),
            ),
          const Expanded(
            child: NotificationsList(
              emptyTitle: 'Aucune notification',
              emptyDescription:
                  'Les réservations, annulations et acomptes de vos clients '
                  'apparaîtront ici.',
            ),
          ),
        ],
      ),
    );
  }
}
