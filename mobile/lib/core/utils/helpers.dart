import 'dart:io';

import 'package:flutter/material.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';

class _NavApp {
  final String name;
  final IconData icon;
  final Uri uri;
  const _NavApp({required this.name, required this.icon, required this.uri});
}

class Helpers {
  /// Detect installed navigation apps and let the user choose which one to open.
  static Future<void> launchNavigation({
    required double latitude,
    required double longitude,
    String? label,
    required BuildContext context,
  }) async {
    final encodedLabel = label != null ? Uri.encodeComponent(label) : '';
    final available = <_NavApp>[];

    // --- Apple Maps (always available on iOS) ---
    if (Platform.isIOS) {
      available.add(_NavApp(
        name: 'Apple Plans',
        icon: Icons.map,
        uri: Uri.parse(
          'https://maps.apple.com/?daddr=$latitude,$longitude&dirflg=d'
          '${encodedLabel.isNotEmpty ? '&q=$encodedLabel' : ''}',
        ),
      ));
    }

    // --- Google Maps ---
    final gmapsUri = Platform.isIOS
        ? Uri.parse(
            'comgooglemaps://?daddr=$latitude,$longitude&directionsmode=driving')
        : Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude');
    final gmapsProbe =
        Platform.isIOS ? Uri.parse('comgooglemaps://') : gmapsUri;
    if (await canLaunchUrl(gmapsProbe)) {
      available.add(_NavApp(
        name: 'Google Maps',
        icon: Icons.directions_car,
        uri: gmapsUri,
      ));
    }

    // --- Waze ---
    final wazeUri = Uri.parse(
      'https://waze.com/ul?ll=$latitude,$longitude&navigate=yes'
      '${encodedLabel.isNotEmpty ? '&q=$encodedLabel' : ''}',
    );
    final wazeProbe = Platform.isIOS ? Uri.parse('waze://') : wazeUri;
    if (await canLaunchUrl(wazeProbe)) {
      available.add(_NavApp(
        name: 'Waze',
        icon: Icons.navigation,
        uri: wazeUri,
      ));
    }

    // --- 2GIS ---
    final dgisUri = Platform.isIOS
        ? Uri.parse(
            'dgis://2gis.ru/routeSearch/rsType/car/to/$longitude,$latitude')
        : Uri.parse(
            'dgis://2gis.ru/routeSearch/rsType/car/to/$longitude,$latitude');
    final dgisProbe = Uri.parse('dgis://');
    if (await canLaunchUrl(dgisProbe)) {
      available.add(_NavApp(
        name: '2GIS',
        icon: Icons.explore,
        uri: dgisUri,
      ));
    }

    // --- Yandex Maps ---
    final yandexUri = Uri.parse(
      'yandexmaps://maps.yandex.ru/?rtext=~$latitude,$longitude&rtt=auto',
    );
    final yandexProbe = Uri.parse('yandexmaps://');
    if (await canLaunchUrl(yandexProbe)) {
      available.add(_NavApp(
        name: 'Yandex Maps',
        icon: Icons.public,
        uri: yandexUri,
      ));
    }

    // --- Android fallback: geo: intent (opens any map app) ---
    if (Platform.isAndroid) {
      available.add(_NavApp(
        name: 'Autre application',
        icon: Icons.open_in_new,
        uri: Uri.parse(
          'geo:$latitude,$longitude?q=$latitude,$longitude'
          '${encodedLabel.isNotEmpty ? '($encodedLabel)' : ''}',
        ),
      ));
    }

    if (!context.mounted) return;

    if (available.isEmpty) {
      showSnackBar(
        context,
        'Aucune application de navigation trouvée',
        isError: true,
      );
      return;
    }

    // If only one option, launch directly.
    if (available.length == 1) {
      await launchUrl(available.first.uri,
          mode: LaunchMode.externalApplication);
      return;
    }

    // Show a bottom sheet picker.
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.secondary,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXXL)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingM),
                const Text(
                  'Ouvrir avec',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: AppTheme.spacingS),
                ...available.map((app) => ListTile(
                      leading: Icon(app.icon, color: AppColors.primary),
                      title: Text(app.name, style: AppTextStyles.bodyMedium),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusLarge),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        launchUrl(app.uri,
                            mode: LaunchMode.externalApplication);
                      },
                    )),
                const SizedBox(height: AppTheme.spacingS),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Show snackbar with message
  static void showSnackBar(BuildContext context, String message,
      {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : Colors.black87,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Show loading dialog
  static void showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: LoadingIndicator(),
      ),
    );
  }

  /// Hide loading dialog
  static void hideLoadingDialog(BuildContext context) {
    Navigator.of(context).pop();
  }

  /// Format phone number for display (mask middle digits)
  static String maskPhoneNumber(String phone) {
    if (phone.length < 8) return phone;
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('+225') && cleaned.length == 12) {
      final digits = cleaned.substring(4);
      return '+225 XX XX ${digits.substring(6)}';
    }
    return phone;
  }
}
