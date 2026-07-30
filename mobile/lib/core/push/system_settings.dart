import 'package:app_settings/app_settings.dart';

import '../utils/logger.dart';

/// Opens the OS notification settings for MyWeli.
///
/// The escape hatch from the one dead end the app can't fix itself: once
/// notifications are denied at the OS level, no in-app toggle can re-enable
/// them — only the system settings can. Best-effort; never throws.
typedef SettingsOpener = Future<void> Function();

Future<void> openSystemNotificationSettings() async {
  try {
    await AppSettings.openAppSettings(type: AppSettingsType.notification);
  } catch (e, s) {
    AppLogger.error(
      'Could not open the notification settings',
      error: e,
      stackTrace: s,
    );
  }
}
