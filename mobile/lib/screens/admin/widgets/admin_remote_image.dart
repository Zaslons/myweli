import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../widgets/common/brand_loader.dart';

/// The only way the admin console draws an image from another origin: a
/// signed KYC or deposit link on R2, a salon's photo on the CDN.
/// Design: docs/design/admin-remote-images.md.
///
/// **Why not `TimedCachedImage`.** The console is Flutter Web on CanvasKit.
/// There, cached_network_image hands the URL to the engine, which loads it
/// through `<img crossorigin="anonymous">` and then `fetch`. Both need the
/// storage to answer with `Access-Control-Allow-Origin` for the console's
/// origin, and R2 never does for `admin.myweli.com`: the private buckets allow
/// a PUT from `myweli.com` only, the public bucket a GET from `myweli.com`
/// only (probed 2026-11-12, spec §1). Every document showed the « image not
/// available » icon.
///
/// [WebHtmlElementStrategy.prefer] has the browser draw a plain `<img>` in a
/// platform view, and a plain `<img>` needs no CORS. Flutter gives that `<img>`
/// `pointer-events: none`, so a `GestureDetector` around this widget still
/// receives the tap that opens the zoom; [fit] is applied by the framework.
/// Off the web the strategy is ignored and this is an ordinary network image.
///
/// **No headers, ever.** An `<img>` cannot send them, and with any header the
/// framework fetches the bytes instead, which needs CORS again.
/// `TimedCachedImage` sends a `User-Agent`; that is one reason it cannot be
/// reused here.
class AdminRemoteImage extends StatelessWidget {
  const AdminRemoteImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.semanticLabel,
  });

  final String url;
  final BoxFit fit;

  /// Null = decorative: the tile's own caption already names the document.
  final String? semanticLabel;

  /// What the failure says. Not « Réessayer »: reloading the same signed link
  /// cannot succeed once it is refused (SYSTEM.md §12).
  static const unavailableLabel = 'Image indisponible';

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      // `frame` stays null until the first frame, on both paths: the framework
      // counts a `WebImageInfo` as a frame too.
      frameBuilder: (context, child, frame, _) =>
          frame == null ? const _Loading() : child,
      errorBuilder: (context, error, stack) => const _Unavailable(),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surface,
      child: Center(child: BrandLoader(size: AppTheme.iconS, fast: true)),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingS),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                size: AppTheme.iconM,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: AppTheme.spacingXS),
              Text(
                AdminRemoteImage.unavailableLabel,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
