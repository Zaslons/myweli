import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

class StoryItem {
  final String id;
  final String title;
  final String assetPath; // svg/png/jpg under assets/
  final String? ctaLabel;
  final String? ctaRoute; // go_router route (e.g. /providers?category=salon)

  const StoryItem({
    required this.id,
    required this.title,
    required this.assetPath,
    this.ctaLabel,
    this.ctaRoute,
  });
}

class StoryViewer extends StatefulWidget {
  final List<StoryItem> stories;
  final int initialIndex;
  final ValueChanged<String>? onViewed;

  const StoryViewer({
    super.key,
    required this.stories,
    this.initialIndex = 0,
    this.onViewed,
  });

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer>
    with TickerProviderStateMixin {
  static const _storyDuration = Duration(seconds: 6);

  late final PageController _pageController;
  late final AnimationController _progress;

  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.stories.length - 1);
    _pageController = PageController(initialPage: _index);

    _progress = AnimationController(vsync: this, duration: _storyDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _next();
        }
      });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onViewed?.call(widget.stories[_index].id);
      _progress.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _next() {
    if (_index >= widget.stories.length - 1) {
      Navigator.of(context).maybePop();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _prev() {
    if (_index <= 0) {
      _progress.forward(from: 0);
      return;
    }
    _pageController.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _pause() => _progress.stop();
  void _resume() {
    if (_progress.isAnimating) return;
    _progress.forward();
  }

  void _onTapDown(TapDownDetails details) {
    final w = MediaQuery.of(context).size.width;
    final x = details.localPosition.dx;
    if (x < w * 0.35) {
      _prev();
    } else {
      _next();
    }
  }

  void _onPageChanged(int newIndex) {
    setState(() => _index = newIndex);
    widget.onViewed?.call(widget.stories[_index].id);
    _progress.forward(from: 0);
  }

  Widget _buildStoryMedia(StoryItem story) {
    final isSvg = story.assetPath.toLowerCase().endsWith('.svg');
    if (isSvg) {
      return SvgPicture.asset(story.assetPath, fit: BoxFit.cover);
    }
    return Image.asset(story.assetPath, fit: BoxFit.cover);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              onTapDown: _onTapDown,
              onLongPressStart: (_) => _pause(),
              onLongPressEnd: (_) => _resume(),
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.stories.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final story = widget.stories[index];
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildStoryMedia(story),
                      // subtle dark gradient for UI legibility
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x99000000),
                              Color(0x00000000),
                              Color(0x99000000),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            // Progress bars
            Positioned(
              left: AppTheme.spacingM,
              right: AppTheme.spacingM,
              top: AppTheme.spacingS,
              child: Row(
                children: List.generate(widget.stories.length, (i) {
                  final isPast = i < _index;
                  final isCurrent = i == _index;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingXS),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusPill),
                        child: Container(
                          height: 3,
                          color: Colors.white.withValues(alpha: 0.25),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: AnimatedBuilder(
                              animation: _progress,
                              builder: (context, _) {
                                final v = isPast
                                    ? 1.0
                                    : isCurrent
                                        ? _progress.value
                                        : 0.0;
                                return FractionallySizedBox(
                                  widthFactor: v,
                                  child: Container(color: Colors.white),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Header
            Positioned(
              left: AppTheme.spacingM,
              right: AppTheme.spacingM,
              top: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.stories[_index].title,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            // CTA
            Positioned(
              left: AppTheme.spacingM,
              right: AppTheme.spacingM,
              bottom: AppTheme.spacingL,
              child: Builder(
                builder: (context) {
                  final s = widget.stories[_index];
                  if (s.ctaLabel == null || s.ctaRoute == null) {
                    return const SizedBox.shrink();
                  }
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondary,
                        foregroundColor: AppColors.primary,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        // Allow both absolute paths and query routes
                        context.push(s.ctaRoute!);
                      },
                      child: Text(s.ctaLabel!),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
