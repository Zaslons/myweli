import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../screens/stories/story_viewer.dart';
import '../../services/story_seen_service.dart';

class AnnouncementStories extends StatefulWidget {
  const AnnouncementStories({super.key});

  @override
  State<AnnouncementStories> createState() => _AnnouncementStoriesState();
}

class _AnnouncementStoriesState extends State<AnnouncementStories> {
  StorySeenService? _seenService;
  Set<String> _seenIds = <String>{};

  // Subtle but lively on a black/white UI: warm gold → soft rose.
  static const Color _ringA = Color(0xFFFFB800);
  static const Color _ringB = Color(0xFFFF4D8D);
  static const double _ringWidth = 2.5;

  @override
  void initState() {
    super.initState();
    _loadSeen();
  }

  Future<void> _loadSeen() async {
    final service = await StorySeenService.create();
    if (!mounted) return;
    setState(() {
      _seenService = service;
      _seenIds = service.getSeenIds();
    });
  }

  List<StoryItem> _stories() {
    return const [
      StoryItem(
        id: 'promo_weekend',
        title: 'Promo Week‑End',
        assetPath: 'assets/images/stories/promo_weekend.svg',
        ctaLabel: 'Voir les salons',
        ctaRoute: '/providers',
      ),
      StoryItem(
        id: 'new_salon',
        title: 'Nouveau salon',
        assetPath: 'assets/images/stories/new_salon.svg',
        ctaLabel: 'Voir les salons',
        ctaRoute: '/providers?category=salon',
      ),
      StoryItem(
        id: 'last_minute',
        title: 'Dernière minute',
        assetPath: 'assets/images/stories/last_minute.svg',
        ctaLabel: 'Réserver',
        ctaRoute: '/providers',
      ),
    ];
  }

  List<StoryItem> _sortedStories(List<StoryItem> stories) {
    // Unseen first; seen pushed to the right.
    final list = stories.toList();
    list.sort((a, b) {
      final aSeen = _seenIds.contains(a.id);
      final bSeen = _seenIds.contains(b.id);
      if (aSeen == bSeen) return 0;
      return aSeen ? 1 : -1;
    });
    return list;
  }

  Future<void> _markSeen(String id) async {
    if (_seenIds.contains(id)) return;
    setState(() => _seenIds = {..._seenIds, id});
    await _seenService?.markSeen(id);
  }

  void _open(BuildContext context, List<StoryItem> stories, int initialIndex) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, anim, _) {
          return FadeTransition(
            opacity: anim,
            child: StoryViewer(
              stories: stories,
              initialIndex: initialIndex,
              onViewed: _markSeen,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stories = _sortedStories(_stories());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 126,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
            itemCount: stories.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: AppTheme.spacingS),
            itemBuilder: (context, index) {
              final s = stories[index];
              final isSeen = _seenIds.contains(s.id);
              final outerRadius = BorderRadius.circular(AppTheme.radiusXL);
              final innerRadius =
                  BorderRadius.circular(AppTheme.radiusXL - _ringWidth);
              return InkWell(
                onTap: () => _open(context, stories, index),
                borderRadius: outerRadius,
                child: Container(
                  width: 92,
                  decoration: BoxDecoration(
                    borderRadius: outerRadius,
                    boxShadow: AppTheme.elevation1,
                    // Unseen: gradient ring. Seen: neutral “empty” ring.
                    gradient: isSeen
                        ? null
                        : const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [_ringA, _ringB],
                          ),
                    border: isSeen
                        ? Border.all(
                            color: AppColors.border,
                            width: _ringWidth,
                          )
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(_ringWidth),
                    child: ClipRRect(
                      borderRadius: innerRadius,
                      child: Stack(
                        children: [
                          // Thumbnail (fills the whole rectangle)
                          Positioned.fill(
                            child: SvgPicture.asset(
                              s.assetPath,
                              fit: BoxFit.cover,
                            ),
                          ),
                          // Bottom fade + label (keeps title readable)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.55),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: Text(
                              s.title,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
