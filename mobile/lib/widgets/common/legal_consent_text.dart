import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/external_link.dart';

/// « En continuant, vous acceptez nos conditions d'utilisation et notre
/// politique de confidentialité. » — with both halves actually reachable (L1).
///
/// **What this replaces was a lie the product told on three screens.** A plain
/// `Text` widget, no link and no route, naming documents that **did not exist**
/// in any surface — and never mentioning privacy at all. Three design specs
/// (`app-auth-social.md:46`, `auth-social-email.md:313`, `web-auth-social.md:52`)
/// describe a "CGU line" here as though it were implemented; it was implemented
/// as static text.
///
/// **A `Wrap` of buttons, not a `TextSpan` with a `TapGestureRecognizer`.** The
/// recognizer is the obvious way to put a link inside a sentence, and it is
/// wrong here twice over: a recognizer span produces **no semantics node**, so a
/// screen-reader user cannot find or activate it, and it has **no box**, so it
/// cannot satisfy §13.2's 48px floor — `test/a11y/tap_target_test.dart` would
/// fail it, correctly. Two real buttons cost a slightly less elegant line break
/// and are actually usable.
///
/// [lead] varies by funnel — « En continuant » on login, « En confirmant » on a
/// booking, « En créant votre compte professionnel » on pro registration —
/// because a sentence that says "continuing" under a button that says "Confirm"
/// reads as boilerplate nobody wrote on purpose.
class LegalConsentText extends StatelessWidget {
  const LegalConsentText({super.key, this.lead = 'En continuant'});

  final String lead;

  @override
  Widget build(BuildContext context) {
    final muted = AppTextStyles.bodySmall.copyWith(
      color: AppColors.textTertiary,
    );
    return Semantics(
      container: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // **No trailing period.** The first version ended with a `Text('.')`
          // child, and the golden showed it orphaned on a line of its own —
          // a `Wrap` breaks between children, and a one-character child is the
          // one most likely to be pushed over. A consent fragment reads fine
          // without it, and a period no user can see is not worth a line.
          Text('$lead, vous acceptez nos ', style: muted),
          _LegalLink(
            label: 'Conditions d’utilisation',
            url: AppConfig.termsUrl,
          ),
          Text(' et notre ', style: muted),
          _LegalLink(
            label: 'Politique de confidentialité',
            url: AppConfig.privacyUrl,
          ),
        ],
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: InkWell(
        onTap: () => openExternalUrl(context, url),
        // §13.2: a real box, not a span. `minHeight` rather than a fixed size
        // so the row still grows at 200% text scale instead of clipping.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            // Horizontal padding widens the box without adding height — the
            // sentence already costs four lines on a 390px login screen, and
            // §13.2 asks for a 48px TARGET, not 48px of whitespace.
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingXS),
            child: Center(
              child: Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
