import 'package:flutter/material.dart';

import '../../../core/constants/failure_messages.dart';
import '../../../core/di/dependency_injection.dart';
import '../../../core/push/system_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../services/interfaces/push_notification_service_interface.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/screen_title.dart';
import '../../../widgets/notifications/mark_all_read_button.dart';
import '../../../widgets/notifications/notifications_list.dart';
import '../../../widgets/push/push_blocked_banner.dart';
import '../../../widgets/push/push_off_card.dart';

/// The salon's notification centre — what the dashboard bell finally opens.
///
/// Fed by the provider-directed events the backend writes for every team
/// member (new booking · client reschedule · client cancellation · deposit
/// proof — docs/design/push-notifications-fcm.md §10). A row's route carries its
/// `?salon=`, so tapping one from a multi-salon account switches to the right
/// salon before opening the booking.
///
/// The list itself is the shared [NotificationsList] (and « Tout marquer comme
/// lu » the shared [MarkAllReadButton]); only the chrome differs
/// from the consumer centre (no bottom nav). The pro app has no preferences
/// screen, so this is also where a salon learns that its phone is blocking
/// notifications — and how to fix it. A phone never asked (« Plus tard » on
/// the dashboard's sheet) gets « Activer les notifications » here
/// (consumer-signin-push.md §2.9, decision 212): until then that salon never
/// heard of a booking, and nothing said so.
class ProNotificationsScreen extends StatefulWidget {
  const ProNotificationsScreen({
    super.key,
    this.openSettings = openSystemNotificationSettings,
    this.permissionStatus,
    this.enablePush,
  });

  /// Test seams.
  final SettingsOpener openSettings;
  final Future<PushPermissionStatus> Function()? permissionStatus;

  /// « Activer les notifications »; defaults to the Pro app's
  /// `PushRegistration.enableFromSettings`.
  final Future<PushPermissionStatus> Function()? enablePush;

  @override
  State<ProNotificationsScreen> createState() => _ProNotificationsScreenState();
}

class _ProNotificationsScreenState extends State<ProNotificationsScreen>
    with WidgetsBindingObserver {
  /// What the system says about this phone; null until read.
  PushPermissionStatus? _osStatus;

  /// The system prompt is open.
  bool _enabling = false;

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
    final read =
        widget.permissionStatus ??
        serviceLocator.pushNotificationService.permissionStatus;
    final status = await read();
    if (!mounted) return;
    setState(() => _osStatus = status);
  }

  /// The same answers as the client's Préférences (§2.9).
  Future<void> _enablePush() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _enabling = true);
    final enable =
        widget.enablePush ??
        serviceLocator.proPushRegistration.enableFromSettings;
    final status = await enable();
    if (!mounted) return;
    setState(() {
      _enabling = false;
      _osStatus = status;
    });
    switch (status) {
      case PushPermissionStatus.granted:
        AppSnackBar.showOn(
          messenger,
          'Notifications activées',
          kind: SnackKind.success,
        );
      case PushPermissionStatus.denied:
        break;
      case PushPermissionStatus.notDetermined:
        AppSnackBar.showOn(
          messenger,
          kGenericErrorMessage,
          kind: SnackKind.error,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const ScreenTitle('Notifications'),
        actions: const [MarkAllReadButton()],
      ),
      body: Column(
        children: [
          if (_osStatus == PushPermissionStatus.notDetermined)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingM,
                AppTheme.spacingM,
                AppTheme.spacingM,
                0,
              ),
              child: PushOffCard(
                onEnable: _enablePush,
                busy: _enabling,
                body: PushOffCard.proBody,
              ),
            ),
          if (_osStatus == PushPermissionStatus.denied)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingM,
                AppTheme.spacingM,
                AppTheme.spacingM,
                0,
              ),
              // The salon's four events (SalonEvent), and the name its
              // phone settings list — never the client's « rappels et
              // confirmations » (promise-honesty-sweep.md T4;
              // salon-client-reschedule-notify.md N4).
              child: PushBlockedBanner(
                onOpenSettings: widget.openSettings,
                body:
                    'Autorisez MyWeli Pro dans les réglages de votre téléphone '
                    'pour être prévenu·e des réservations, reports, '
                    'annulations et acomptes de vos clients.',
              ),
            ),
          const Expanded(
            child: NotificationsList(
              emptyTitle: 'Aucune notification',
              emptyDescription:
                  'Les réservations, reports, annulations et acomptes de vos '
                  'clients apparaîtront ici.',
            ),
          ),
        ],
      ),
    );
  }
}
