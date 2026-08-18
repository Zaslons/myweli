import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/utils/external_link.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/empty_state.dart';

/// The blocking screen for a build below the floor.
///
/// ## It replaces the application; it does not sit inside it
///
/// `main()` calls `runApp(UpdateRequiredApp(...))` and **returns**, exactly as
/// `misconfiguredBuildScreen()` does. That is the only genuinely inescapable
/// shape in this codebase: no route is ever created, so there is nothing to pop
/// to; DI never runs; and — the reason a router-based gate would not do — a
/// tapped notification replays through `AppRouter.router.push`, which would
/// stack a real screen *on top of* any route-level block.
///
/// ## Why `EmptyState` rather than a bespoke screen
///
/// `EmptyState` reads `AppColors`/`AppTextStyles`/`AppTheme` **statically**,
/// never through `Theme.of(context)`, so it renders correctly under a root with
/// no DI and no `ThemeData` — the same property `build_config_guard` relies on.
/// SYSTEM.md §11: reuse before you build. It already carries the 48-dp target,
/// the `Flexible` button label (§21 row 64) and the
/// `LayoutBuilder`→`SingleChildScrollView` that starts scrolling the instant
/// content stops fitting, which is what keeps this legible at 200% text.
///
/// **No `AppBar`**: inside a route it paints a back button, and omitting it
/// sidesteps §21 row 79 (bar titles ellipsizing at 200%) by construction. The
/// `Scaffold` stays, because `openExternalUrl` captures a `ScaffoldMessenger`.
class UpdateRequiredApp extends StatelessWidget {
  const UpdateRequiredApp({
    super.key,
    this.updateUrl,
    this.isPro = false,
    this.onOpen,
  });

  /// Null when the platform has no store listing yet. The backend refuses to
  /// send `update_required` in that case, so this is unreachable in production
  /// — but a dead button is worse than no button, so the screen renders without
  /// one rather than trusting that guarantee.
  final String? updateUrl;
  final bool isPro;

  /// Test seam for the launcher, mirroring `push_blocked_banner.dart`'s opener.
  final void Function(BuildContext, String)? onOpen;

  @override
  Widget build(BuildContext context) {
    final open = onOpen ?? openExternalUrl;
    return MaterialApp(
      title: 'MyWeli',
      debugShowCheckedModeBanner: false,
      // The repo idiom (`main.dart:132`): `GlobalMaterialLocalizations.delegates`
      // rather than a hand-listed pair — it includes the Cupertino delegate.
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('fr', 'FR')],
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Builder(
            builder: (context) => Column(
              children: [
                // The message scrolls…
                Expanded(
                  child: EmptyState(
                    icon: Icons.system_update_outlined,
                    title: 'Mise à jour requise',
                    description: isPro
                        ? 'Cette version de MyWeli n’est plus prise en charge. '
                              'Installez la dernière version pour continuer à '
                              'gérer votre salon.'
                        : 'Cette version de MyWeli n’est plus prise en charge. '
                              'Installez la dernière version pour continuer à '
                              'prendre vos rendez-vous.',
                  ),
                ),
                // …and the action does NOT.
                //
                // `EmptyState` normally carries its own action, and reusing that
                // is what the first draft did. The 2× golden showed why it is
                // wrong *here*: the column grows past the 780dp floor phone and
                // the button lands below the fold. On any other screen that is
                // fine — you scroll, or you leave. **This is the one screen a
                // user cannot leave**, so its single way out must never have to
                // be hunted for. The message may scroll; the exit may not.
                //
                // No retry either (SYSTEM.md §12: the way out is a retry only
                // when retrying can succeed). The only way out is the store.
                if (updateUrl != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.spacingXL,
                      0,
                      AppTheme.spacingXL,
                      AppTheme.spacingXL,
                    ),
                    child: AppButton(
                      text: 'Mettre à jour',
                      onPressed: () => open(context, updateUrl!),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
