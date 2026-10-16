import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/common/app_snack_bar.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'phone_numbering.dart';

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
      available.add(
        _NavApp(
          name: 'Apple Plans',
          icon: Icons.map,
          uri: Uri.parse(
            'https://maps.apple.com/?daddr=$latitude,$longitude&dirflg=d'
            '${encodedLabel.isNotEmpty ? '&q=$encodedLabel' : ''}',
          ),
        ),
      );
    }

    // --- Google Maps ---
    final gmapsUri = Platform.isIOS
        ? Uri.parse(
            'comgooglemaps://?daddr=$latitude,$longitude&directionsmode=driving',
          )
        : Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude',
          );
    final gmapsProbe = Platform.isIOS
        ? Uri.parse('comgooglemaps://')
        : gmapsUri;
    if (await canLaunchUrl(gmapsProbe)) {
      available.add(
        _NavApp(name: 'Google Maps', icon: Icons.directions_car, uri: gmapsUri),
      );
    }

    // --- Waze ---
    final wazeUri = Uri.parse(
      'https://waze.com/ul?ll=$latitude,$longitude&navigate=yes'
      '${encodedLabel.isNotEmpty ? '&q=$encodedLabel' : ''}',
    );
    final wazeProbe = Platform.isIOS ? Uri.parse('waze://') : wazeUri;
    if (await canLaunchUrl(wazeProbe)) {
      available.add(
        _NavApp(name: 'Waze', icon: Icons.navigation, uri: wazeUri),
      );
    }

    // --- 2GIS ---
    final dgisUri = Platform.isIOS
        ? Uri.parse(
            'dgis://2gis.ru/routeSearch/rsType/car/to/$longitude,$latitude',
          )
        : Uri.parse(
            'dgis://2gis.ru/routeSearch/rsType/car/to/$longitude,$latitude',
          );
    final dgisProbe = Uri.parse('dgis://');
    if (await canLaunchUrl(dgisProbe)) {
      available.add(_NavApp(name: '2GIS', icon: Icons.explore, uri: dgisUri));
    }

    // --- Yandex Maps ---
    final yandexUri = Uri.parse(
      'yandexmaps://maps.yandex.ru/?rtext=~$latitude,$longitude&rtt=auto',
    );
    final yandexProbe = Uri.parse('yandexmaps://');
    if (await canLaunchUrl(yandexProbe)) {
      available.add(
        _NavApp(name: 'Yandex Maps', icon: Icons.public, uri: yandexUri),
      );
    }

    // --- Android fallback: geo: intent (opens any map app) ---
    if (Platform.isAndroid) {
      available.add(
        _NavApp(
          name: 'Autre application',
          icon: Icons.open_in_new,
          uri: Uri.parse(
            'geo:$latitude,$longitude?q=$latitude,$longitude'
            '${encodedLabel.isNotEmpty ? '($encodedLabel)' : ''}',
          ),
        ),
      );
    }

    if (!context.mounted) return;

    if (available.isEmpty) {
      AppSnackBar.show(
        context,
        'Aucune application de navigation trouvée',
        kind: SnackKind.error,
      );
      return;
    }

    // If only one option, launch directly.
    if (available.length == 1) {
      await launchUrl(
        available.first.uri,
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    // Show a bottom sheet picker.
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.secondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXXL),
        ),
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
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingM),
                const Text('Ouvrir avec', style: AppTextStyles.titleMedium),
                const SizedBox(height: AppTheme.spacingS),
                ...available.map(
                  (app) => ListTile(
                    leading: Icon(app.icon, color: AppColors.primary),
                    title: Text(app.name, style: AppTextStyles.bodyMedium),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      launchUrl(app.uri, mode: LaunchMode.externalApplication);
                    },
                  ),
                ),
                const SizedBox(height: AppTheme.spacingS),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Speak an off-focus change (a SnackBar, a list reload — things a screen
  /// reader doesn't read on its own) to TalkBack/VoiceOver. Fire-and-forget.
  /// Wraps the post-3.35 `sendAnnouncement` so call sites don't repeat the
  /// `View.of` + `Directionality.of` + `unawaited` boilerplate.
  static void announce(BuildContext context, String message) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ),
    );
  }

  /// Show loading dialog
  static void showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: LoadingIndicator()),
    );
  }

  /// Hide loading dialog
  static void hideLoadingDialog(BuildContext context) {
    Navigator.of(context).pop();
  }

  /// [phone] for display with its middle hidden — « +225 07••••••56 »: the
  /// calling code, the first two and the last two national digits, a `•` for
  /// each digit between (docs/design/phone-leftovers.md §5).
  ///
  /// It knows no length. It used to mask only `+225` plus the pre-2021 8
  /// digits, a rule written here, outside the §18 seam — so every number of
  /// today, Ivorian or not, went through whole and printed in clear. The
  /// calling code is the longest one the number starts with, the reading
  /// `PhoneNumberField` gives a stored number (`+33…` is France, not `+336`) —
  /// `PhoneNumbering.callingCodeOf`. A value with nothing to hide between its four shown digits comes back as
  /// it was.
  static String maskPhoneNumber(String phone) {
    final cleaned = PhoneNumbering.normalize(phone);
    final international = cleaned.startsWith('+');
    final digits = international ? cleaned.substring(1) : cleaned;
    if (!RegExp(r'^\d+$').hasMatch(digits)) return phone;
    final callingCode = international
        ? PhoneNumbering.callingCodeOf(digits)
        : '';
    final national = digits.substring(callingCode.length);
    if (national.length <= 4) return phone;
    final masked =
        '${national.substring(0, 2)}'
        '${'•' * (national.length - 4)}'
        '${national.substring(national.length - 2)}';
    if (!international) return masked;
    return callingCode.isEmpty ? '+$masked' : '+$callingCode $masked';
  }
}
