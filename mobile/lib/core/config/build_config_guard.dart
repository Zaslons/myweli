import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'app_config.dart';

/// Refuses to start a **release** build that was compiled without the backend
/// `--dart-define`s (docs/design/infra-staging.md §1.3).
///
/// ## Why a screen and not a throw
///
/// The failure being caught is *silence*: `USE_API_BACKEND` defaults to false
/// and `API_BASE_URL` defaults to localhost, so a TestFlight or internal-track
/// build missing one define runs entirely on in-app mocks and looks completely
/// healthy — full salon list, working search, bookings that appear to succeed.
/// A tester exercises it, reports that staging works, and nothing was tested.
///
/// Throwing would crash on launch, which is unmissable but indistinguishable
/// from a real crash, and catastrophic in the one case that must never happen:
/// such a build reaching the store. A blocking screen is equally unmissable to
/// whoever opens it, names the exact missing define, and cannot be mistaken for
/// anything else.
///
/// ## Why release only
///
/// Debug and profile builds run on mocks as the normal way to work, and every
/// widget test runs in debug — so this is inert there by construction rather
/// than by an opt-out someone has to remember.
Widget? misconfiguredBuildScreen() {
  final reason = AppConfig.backendMisconfiguration;
  if (reason == null) return null;
  return _MisconfiguredBuildApp(reason: reason);
}

class _MisconfiguredBuildApp extends StatelessWidget {
  const _MisconfiguredBuildApp({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    // Deliberately self-contained: no router, no DI, no ThemeData lookup — this
    // runs *instead of* app startup, so it must not depend on anything startup
    // does. The design tokens are safe to use regardless: they are compile-time
    // constants, not a resolved theme (SYSTEM.md §5, §20).
    //
    // English, not French — the audience is whoever produced the build, never a
    // customer, and every other string here is the name of a --dart-define.
    return MaterialApp(
      // Declared to satisfy the repo-wide gate in `test/unit/french_test.dart`,
      // which allows no MaterialApp without them — an exemption list is the
      // thing that rots. Inert here: every string on this screen is English on
      // purpose (the audience is whoever produced the build, not a customer)
      // and nothing Material localises is rendered.
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('fr', 'FR')],
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppColors.error,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacingL),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.build_circle_outlined,
                    color: Colors.white,
                    size: AppTheme.spacingXXL, // 48 — the largest icon token
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  Text(
                    'BUILD MISCONFIGURED',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingSM),
                  Text(
                    reason,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  Text(
                    'This release build would have run on in-app mock data '
                    'while appearing to work normally. Do not distribute it.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  Text(
                    'API_BASE_URL = ${AppConfig.apiBaseUrl}\n'
                    'USE_API_BACKEND = ${AppConfig.useApiBackend}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
