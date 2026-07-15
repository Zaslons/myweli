import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/di/dependency_injection.dart';
import '../../core/push/system_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/notification_preferences_provider.dart';
import '../../services/interfaces/push_notification_service_interface.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/push/push_blocked_banner.dart';

/// Consumer notification preferences (FR-NOTIF-004): three opt-out toggles,
/// each persisted (optimistic, revert on failure). The backend respects these
/// at send time.
///
/// It also surfaces the OS-level state: once notifications are DENIED in the
/// system settings, none of these toggles can bring them back, so the screen
/// says so and offers the way out (docs/design/push-notifications-app.md).
/// Design: docs/design/notification-preferences.md.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({
    super.key,
    this.openSettings = openSystemNotificationSettings,
    this.permissionStatus,
  });

  /// Test seams.
  final SettingsOpener openSettings;
  final Future<PushPermissionStatus> Function()? permissionStatus;

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> with WidgetsBindingObserver {
  bool _osDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationPreferencesProvider>().load();
      _refreshOsPermission();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the system settings: the banner must disappear the
    // moment the user has enabled notifications there.
    if (state == AppLifecycleState.resumed) _refreshOsPermission();
  }

  Future<void> _refreshOsPermission() async {
    final read = widget.permissionStatus ??
        serviceLocator.pushNotificationService.permissionStatus;
    final status = await read();
    if (!mounted) return;
    setState(() => _osDenied = status == PushPermissionStatus.denied);
  }

  Future<void> _toggle(Future<bool> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<NotificationPreferencesProvider>();
    final ok = await action();
    if (!ok && mounted) {
      messenger.showSnackBar(
        SnackBar(
          content:
              Text(provider.error ?? 'Impossible d\'enregistrer. Réessayez.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Préférences de notification')),
      body: Consumer<NotificationPreferencesProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) return const LoadingIndicator();

          if (provider.loadFailed) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingL),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: AppTheme.iconXL, color: AppColors.error),
                    const SizedBox(height: AppTheme.spacingM),
                    Text(
                      provider.error ?? 'Erreur lors du chargement',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingM),
                    AppButton(
                      text: 'Réessayer',
                      type: AppButtonType.secondary,
                      onPressed: () => provider.load(),
                    ),
                  ],
                ),
              ),
            );
          }

          final prefs = provider.prefs;
          return ListView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            children: [
              if (_osDenied)
                PushBlockedBanner(onOpenSettings: widget.openSettings),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                  boxShadow: AppTheme.elevation1,
                ),
                child: Column(
                  children: [
                    _PrefSwitch(
                      title: 'Rappels de rendez-vous',
                      subtitle: 'Rappels 24 h et 2 h avant vos rendez-vous.',
                      value: prefs.reminders,
                      onChanged: (v) => _toggle(() => provider.setReminders(v)),
                    ),
                    const Divider(height: 1),
                    _PrefSwitch(
                      title: 'Offres & promotions',
                      subtitle: 'Offres, nouveautés et relances.',
                      value: prefs.marketing,
                      onChanged: (v) => _toggle(() => provider.setMarketing(v)),
                    ),
                    const Divider(height: 1),
                    _PrefSwitch(
                      title: 'Notifications push',
                      subtitle: 'Notifications sur cet appareil.',
                      value: prefs.push,
                      onChanged: (v) => _toggle(() => provider.setPush(v)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingM),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: AppTheme.iconS, color: AppColors.textTertiary),
                  const SizedBox(width: AppTheme.spacingS),
                  Expanded(
                    child: Text(
                      'Les confirmations et changements de rendez-vous sont '
                      'toujours envoyés.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PrefSwitch extends StatelessWidget {
  const _PrefSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title, style: AppTextStyles.bodyLarge),
      subtitle: Text(
        subtitle,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
