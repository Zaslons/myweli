import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/motion.dart';
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

  // On-brand "unseen" ring: `AppColors.gold` (3.15:1 on background — it clears the non-text
  // floor); seen → the neutral `border`. It used to borrow `starRating`, which at
  // 1.62:1 made the ring all but invisible — and `starRating` is the fill of a
  // rating star and nothing else (docs/design/SYSTEM.md §3.5, §19).
  //
  // §13.6 (register row 25): the ring must not lean on HUE alone. So unseen is a
  // THICK gold ring, seen a THIN neutral one — a difference of width (and the
  // title weight below) that survives greyscale, not just colour.
  static const double _unseenRingWidth = 3;
  static const double _seenRingWidth = 1;

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
        transitionDuration: AppMotion.base,
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
        // A13, §21 row 62 — **the fixed height goes with the fixed width.**
        // `SizedBox(height: 126)` is a box that contains text, which §13.3
        // forbids outright; it survived only because the title is `maxLines: 2`
        // and two lines of `labelSmall` at 2× still fit 126.
        //
        // **It is a COMPUTED height, not an intrinsic one, and the golden
        // ledger is why.** The obvious move — drop the bound and let the row
        // size itself, as `CategoryChips` and `client_list_screen` each did —
        // collapses these cards to a bare gold ring: the card's content is a
        // `Stack` whose children are all `Positioned.fill`, and positioned
        // children contribute **nothing** to intrinsic height. So the strip has
        // no intrinsic height to take. Those precedents work because their chips
        // wrap real text; this one does not, and the regeneration showed it as
        // three thin bars before anything else did.
        SizedBox(
          height: _stripHeight(context),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
            child: Row(
              children: [
                for (var index = 0; index < stories.length; index++) ...[
                  if (index > 0) const SizedBox(width: AppTheme.spacingS),
                  Builder(
                    builder: (context) {
                      final s = stories[index];
                      final isSeen = _seenIds.contains(s.id);
                      final ringWidth = isSeen
                          ? _seenRingWidth
                          : _unseenRingWidth;
                      final outerRadius = BorderRadius.circular(
                        AppTheme.radiusXL,
                      );
                      final innerRadius = BorderRadius.circular(
                        AppTheme.radiusXL - ringWidth,
                      );
                      return Semantics(
                        button: true,
                        label:
                            '${s.title}, ${isSeen ? 'déjà vue' : 'nouvelle'}',
                        child: InkWell(
                          onTap: () => _open(context, stories, index),
                          borderRadius: outerRadius,
                          child: Container(
                            width: _cardWidth(context, ringWidth),
                            decoration: BoxDecoration(
                              borderRadius: outerRadius,
                              boxShadow: AppTheme.elevation1,
                              // Unseen: gold ring. Seen: neutral “empty” ring.
                              border: Border.all(
                                color: isSeen
                                    ? AppColors.border
                                    : AppColors.gold,
                                width: ringWidth,
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(ringWidth),
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
                                              Colors.black.withValues(
                                                alpha: 0.55,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: _titleInset,
                                      right: _titleInset,
                                      bottom: _titleInset,
                                      child: Text(
                                        s.title,
                                        style: AppTextStyles.labelSmall.copyWith(
                                          color: Colors.white,
                                          // §13.6 second cue: unseen reads bold, seen regular.
                                          fontWeight: isSeen
                                              ? FontWeight.w500
                                              : FontWeight.w700,
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
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The width a story card needs so its title never breaks inside a word
  /// (A13, §21 row 62).
  ///
  /// The card was a flat `width: 92`, and §13.3 forbids a fixed width around
  /// text for exactly the reason this file demonstrates: at 360×2× the title's
  /// box is **64dp** and « Week‑End » — one token, because the hyphen at
  /// `:52` is **U+2011, non-breaking** — needs **104**. The device photographed
  /// « Prom/o W… ».
  ///
  /// **Measured, and the number that matters is 1.20×, not 2×.** Against the
  /// SDK's own Roboto the 64dp box loses « Week‑End » just past **1.20×**,
  /// « Nouveau » at 1.38× and « Dernière » at 1.43×. All three titles break, so
  /// swapping the U+2011 for a breaking hyphen would fix one of three — and a
  /// 1.3× branch, the idiom the dashboard and the salon action bar use, would
  /// arrive **late**. This is why the fix is a width that tracks the scale
  /// rather than a threshold that switches layout.
  ///
  /// The shape is `ProviderCard.minGridCellWidth`'s: `textScaledBound` over the
  /// chrome that must not move plus the text box at 1×. Because that is
  /// `constant + max(text, scale·text)`, it returns **exactly 92.0 at 1×** and
  /// below — the 1× golden is byte-identical — and clears every token to 3×.
  ///
  /// **`ringWidth` is an argument, not a constant, and that is a defect this
  /// fix also closes.** `Container` applies `decoration.padding` (the border's
  /// dimensions) *on top of* the explicit `Padding(all: ringWidth)`, so the ring
  /// is inset twice and the text box was `92 − 4·ring − 16` — i.e. **64dp when
  /// unseen and 72dp when seen**. The title's width depended on whether the user
  /// had opened the story.
  static double _cardWidth(BuildContext context, double ringWidth) {
    // **The scaling term uses the UNSEEN ring, always**, and the review is why.
    // Computing `chrome` from the card's own ring made a seen card 8dp wider
    // than an unseen one above 1× — in the same row, and changing the instant
    // `_markSeen` fired. The old fixed 92 had one width for both; moving the
    // asymmetry from the text box into the card outline would have traded one
    // defect for a subtler one.
    //
    // The unseen ring is the correct basis because it is the tighter box: a
    // card sized for it clears the title whatever ring it ends up drawing.
    const worstChrome = _titleInset * 2 + _unseenRingWidth * 4;
    final scaled = AppTheme.textScaledBound(
      context,
      constant: worstChrome,
      text: _baseCardWidth - worstChrome,
    );
    // `ringWidth` still matters for the card's own geometry, not its width.
    assert(ringWidth > 0);
    return scaled;
  }

  /// The card at 1×, unchanged from the constant it replaces.
  static const double _baseCardWidth = 92.0;

  /// The strip at 1×, unchanged from the constant it replaces.
  static const double _baseStripHeight = 126.0;

  /// Two lines of `labelSmall` plus the title's bottom inset — the only part of
  /// the card that grows with the font. `labelSmall` is 11px on a 16px line
  /// (`text_styles.dart`), so 32 + 8.
  static const double _titleBlock = 16.0 * 2 + _titleInset;

  /// The strip's height at the current OS text scale.
  ///
  /// Same shape as the width, and same property: `textScaledBound` returns
  /// **exactly 126.0 at 1×** and below, so the 1× golden does not move, while
  /// the image keeps its share and only the title block grows.
  static double _stripHeight(BuildContext context) => AppTheme.textScaledBound(
    context,
    constant: _baseStripHeight - _titleBlock,
    text: _titleBlock,
  );

  /// The title's inset inside the clipped image (`Positioned(left/right/bottom)`).
  static const double _titleInset = AppTheme.spacingS;
}
