import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/reload_on_sign_in.dart';
import '../../core/constants/failure_messages.dart';
import '../../core/di/dependency_injection.dart';
import '../../core/push/system_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/notification_preferences.dart';
import '../../providers/notification_preferences_provider.dart';
import '../../services/interfaces/push_notification_service_interface.dart';
import '../../widgets/common/app_async_view.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/app_skeleton.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/screen_title.dart';
import '../../widgets/push/push_blocked_banner.dart';
import '../../widgets/push/push_off_card.dart';

/// Consumer notification preferences (FR-NOTIF-004): three opt-out toggles,
/// each persisted (optimistic, revert on failure). The backend respects these
/// at send time.
///
/// It also surfaces the OS-level state: once notifications are DENIED in the
/// system settings, none of these toggles can bring them back, so the screen
/// says so and offers the way out (docs/design/push-notifications-app.md).
/// Never asked yet (« Plus tard », or no booking so far), it offers « Activer
/// les notifications » (consumer-signin-push.md §2.9, decision 209).
/// Design: docs/design/notification-preferences.md.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({
    super.key,
    this.openSettings = openSystemNotificationSettings,
    this.permissionStatus,
    this.enablePush,
  });

  /// Test seams.
  final SettingsOpener openSettings;
  final Future<PushPermissionStatus> Function()? permissionStatus;

  /// « Activer les notifications »; defaults to
  /// `PushRegistration.enableFromSettings`.
  final Future<PushPermissionStatus> Function()? enablePush;

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen>
    with WidgetsBindingObserver, ReloadOnSignIn<NotificationPreferencesScreen> {
  /// A session that ended here opens the sign-in over this screen and comes
  /// back to it (consumer-signin-push.md §2.7): the preferences load again.
  @override
  void reloadForSignIn() {
    context.read<NotificationPreferencesProvider>().load();
    _refreshOsPermission();
  }

  /// What the system says about this phone; null until read.
  PushPermissionStatus? _osStatus;

  /// The system prompt is open.
  bool _enabling = false;

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
    final read =
        widget.permissionStatus ??
        serviceLocator.pushNotificationService.permissionStatus;
    final status = await read();
    if (!mounted) return;
    setState(() => _osStatus = status);
  }

  /// « Activer les notifications » (§2.9): granted → the token is registered
  /// and it is said; refused → the card becomes the blocked banner; no
  /// answer (the adapter's « not determined » on failure) → the card stays,
  /// and the generic sentence says it did not work.
  Future<void> _enablePush() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _enabling = true);
    final enable =
        widget.enablePush ?? serviceLocator.pushRegistration.enableFromSettings;
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

  Future<void> _toggle(Future<bool> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<NotificationPreferencesProvider>();
    final ok = await action();
    if (!ok && mounted) {
      AppSnackBar.showOn(
        messenger,
        provider.error ?? 'Impossible d’enregistrer. Réessayez.',
        kind: SnackKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Cards are `secondary` on `background` (SYSTEM §3.1): the step that
      // lifts them, now they have no shadow (B9.8 F2).
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const ScreenTitle('Préférences')),
      body: Consumer<NotificationPreferencesProvider>(
        builder: (context, provider, _) {
          return AppAsyncView<NotificationPreferences>(
            isLoading: provider.isLoading,
            error: provider.loadFailed
                ? provider.error ?? kGenericErrorMessage
                : null,
            data: provider.loadedPrefs,
            isEmpty: (_) => false,
            loading: const SkeletonTileList(count: 3, leading: false),
            empty: const SizedBox.shrink(),
            onRetry: provider.load,
            builder: (context, prefs) => _form(provider, prefs),
          );
        },
      ),
    );
  }

  Widget _form(
    NotificationPreferencesProvider provider,
    NotificationPreferences prefs,
  ) {
    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      children: [
        if (_osStatus == PushPermissionStatus.denied)
          PushBlockedBanner(onOpenSettings: widget.openSettings),
        if (_osStatus == PushPermissionStatus.notDetermined)
          PushOffCard(onEnable: _enablePush, busy: _enabling),
        AppCard(
          // The card IS the `Material` the tile paints its ink on — what the
          // transparent layer under a decorated box was there for (Flutter 3.44's
          // `_findIntermediateWidget` assertion); a list of rows needs no padding.
          padding: EdgeInsets.zero,
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
                // The account's switch, not this phone's: the server reads it
                // before any push and sends to every device of the account
                // (decision 211).
                subtitle: 'Sur tous les téléphones connectés à votre compte.',
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
            const Icon(
              Icons.info_outline,
              size: AppTheme.iconS,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: AppTheme.spacingS),
            Expanded(
              child: Text(
                // « envoyés » was true only while push was on: with push off,
                // and SMS and WhatsApp off, nothing is sent — what always
                // happens is the entry in « Actu » (decision 211).
                'Les confirmations et changements de rendez-vous restent '
                'toujours dans « Actu ».',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ],
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
