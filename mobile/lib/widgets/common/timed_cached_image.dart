import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:myweli/widgets/common/brand_loader.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/utils/timeout_cache_manager.dart';

class TimedCachedImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Duration timeout;

  /// The screen-reader name for a MEANINGFUL image (a salon photo the user is
  /// meant to perceive). Left null, the image is treated as **decorative** and
  /// hidden from the semantics tree (`excludeFromSemantics`) — the WCAG-correct
  /// default, since most images sit inside a card that already announces its
  /// name (§13.4).
  final String? semanticLabel;

  const TimedCachedImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.timeout = const Duration(seconds: 12),
    this.semanticLabel,
  });

  @override
  State<TimedCachedImage> createState() => _TimedCachedImageState();
}

class _TimedCachedImageState extends State<TimedCachedImage> {
  Timer? _timer;
  bool _timedOut = false;
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant TimedCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _timer?.cancel();
      _timedOut = false;
      _reloadToken = 0;
      _startTimer();
    }
  }

  void _startTimer() {
    _timer = Timer(widget.timeout, () {
      if (!mounted) return;
      setState(() {
        _timedOut = true;
      });
    });
  }

  void _retry() {
    setState(() {
      _timedOut = false;
      _reloadToken++;
    });
    _timer?.cancel();
    _startTimer();
  }

  void _cancelTimeoutOverlayIfNeeded() {
    _timer?.cancel();
    if (!_timedOut) return;
    // Avoid setState during build callbacks; schedule it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_timedOut) return;
      setState(() => _timedOut = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl.startsWith('asset:')) {
      final assetPath = widget.imageUrl.substring('asset:'.length);
      final bool decorative = widget.semanticLabel == null;
      final Widget assetWidget = assetPath.toLowerCase().endsWith('.svg')
          ? SvgPicture.asset(
              assetPath,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              semanticsLabel: widget.semanticLabel,
              excludeFromSemantics: decorative,
            )
          : Image.asset(
              assetPath,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              semanticLabel: widget.semanticLabel,
              excludeFromSemantics: decorative,
            );

      if (widget.borderRadius != null) {
        return ClipRRect(
            borderRadius: widget.borderRadius!, child: assetWidget);
      }
      return assetWidget;
    }

    final content = CachedNetworkImage(
      key: ValueKey('${widget.imageUrl}#$_reloadToken'),
      imageUrl: widget.imageUrl,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      cacheManager: TimeoutCacheManager.images,
      httpHeaders: const {'User-Agent': 'Myweli/1.0'},
      imageBuilder: (context, imageProvider) {
        _cancelTimeoutOverlayIfNeeded();
        return Image(
          image: imageProvider,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          semanticLabel: widget.semanticLabel,
          excludeFromSemantics: widget.semanticLabel == null,
        );
      },
      placeholder: (context, url) => Container(
        width: widget.width,
        height: widget.height,
        color: AppColors.surface,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: BrandLoader(size: AppTheme.iconS, fast: true),
        ),
      ),
      errorWidget: (context, url, error) {
        _cancelTimeoutOverlayIfNeeded();
        return Container(
          width: widget.width,
          height: widget.height,
          color: AppColors.surface,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported),
        );
      },
    );

    Widget wrapped = content;
    if (widget.borderRadius != null) {
      wrapped = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: wrapped,
      );
    }

    if (!_timedOut) return wrapped;

    return Stack(
      children: [
        wrapped,
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.25),
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('Réessayer',
                  style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }
}
