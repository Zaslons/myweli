import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:provider/provider.dart';

import '../../core/constants/salon_categories.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/search_text.dart';
import '../../models/provider.dart' as models;
import '../../providers/provider_provider.dart';
import '../../providers/salon_search_controller.dart';
import '../../services/interfaces/provider_service_interface.dart';
import '../../widgets/common/app_async_view.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_chip.dart';
import '../../widgets/common/app_skeleton.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/commune_picker_sheet.dart';
import '../../widgets/common/commune_pill.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/inline_feedback.dart';
import '../../widgets/common/screen_title.dart';
import '../../widgets/home/category_chips.dart';
import '../../widgets/provider/provider_card.dart';

/// « Salons & Barbiers »: the search (docs/design/consumer-search.md §2).
///
/// `/providers?category=nails` (a home chip) opens it with that chip on;
/// `/providers?focus=search` (the home's « Rechercher un salon… ») with the
/// keyboard up. The parameters are read once, at creation (§5).
class ProviderListScreen extends StatefulWidget {
  /// A category key from the URL. Anything outside the taxonomy — the
  /// website's old `nail`, a stale link — opens on « Tous » (§2.4).
  final String? category;

  /// Put the cursor in the search field, keyboard up (§2.1 step 1).
  final bool focusSearch;

  const ProviderListScreen({
    super.key,
    this.category,
    this.focusSearch = false,
  });

  @override
  State<ProviderListScreen> createState() => _ProviderListScreenState();
}

class _ProviderListScreenState extends State<ProviderListScreen> {
  late final SalonSearchController _search;
  final _field = TextEditingController();
  bool _isGrid = false;

  /// The last answer announced to a screen reader (§2.5).
  int _announced = 0;

  @override
  void initState() {
    super.initState();
    _search = SalonSearchController(
      providers: Provider.of<ProviderProvider>(context, listen: false),
      category: discoveryCategory(widget.category)?.key,
    )..addListener(_announceAnswer);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_announceAnswer)
      ..dispose();
    _field.dispose();
    super.dispose();
  }

  /// Once each search has answered — not on every key, and even when the
  /// count did not change between two searches, where a live region would
  /// say nothing (§2.5).
  void _announceAnswer() {
    if (_search.answers == _announced || !mounted) return;
    _announced = _search.answers;
    final sentence = _statusSentence();
    if (sentence != null) Helpers.announce(context, sentence);
  }

  String? _statusSentence() {
    final error = _search.error;
    final items = _search.items;
    if (error != null && (items == null || items.isEmpty)) {
      return 'Chargement impossible. $error';
    }
    if (items == null) return null;
    if (items.isEmpty) {
      return _emptyCopy(
        Provider.of<ProviderProvider>(context, listen: false),
      ).title;
    }
    return _countLabel();
  }

  Future<void> _openCommunePicker(ProviderProvider provider) async {
    final choice = await showCommunePicker(
      context,
      selected: provider.selectedCommune,
    );
    if (choice == null) return;
    await provider.setCommune(choice.commune);
  }

  void _clearSearch() {
    _field.clear();
    _search.onTextChanged('');
  }

  /// « 1 salon », « 42 salons », « 42 salons à Cocody » — the server's
  /// `total`, not the salons on screen (§2.5).
  String _countLabel() {
    final n = _search.total;
    final noun = n <= 1 ? 'salon' : 'salons';
    final commune = _search.shown?.commune;
    return commune != null ? '$n $noun à $commune' : '$n $noun';
  }

  /// The count line: « Recherche… » while a new search is out over the
  /// results shown; nothing while the first page loads or when there is
  /// nothing — the empty state says it (§2.5).
  String? _countLine() {
    if (_search.isSearchingAgain) return 'Recherche…';
    final items = _search.items;
    if (_search.isLoading || items == null || items.isEmpty) return null;
    return _countLabel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // **No actions, deliberately** (A15, §21 row 79). « Salons & Barbiers »
      // is 257dp at the 1.34× clamp and a pushed bar carrying one icon action
      // leaves 232 — so the title lost, and the title is the half that cannot
      // give: it is a promise to *two* audiences, and « Salons » drops one of
      // them. The grid/list toggle moved into the results row instead, which is
      // where a control over the results belongs anyway.
      appBar: AppBar(title: const ScreenTitle('Salons & Barbiers')),
      body: Consumer<ProviderProvider>(
        builder: (context, provider, _) => ListenableBuilder(
          listenable: _search,
          builder: (context, _) => Column(
            children: [
              _buildSearchField(),
              _buildFilterBar(provider),
              Expanded(child: _buildResults(provider)),
            ],
          ),
        ),
      ),
    );
  }

  /// §2.2 item 2: a magnifier, the hint, and ✕ while it holds text.
  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingM,
        AppTheme.spacingM,
        AppTheme.spacingM,
        0,
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _field,
        builder: (context, value, _) => AppTextField(
          controller: _field,
          hint: 'Salon, prestation ou commune',
          semanticsLabel: 'Rechercher un salon',
          autofocus: widget.focusSearch,
          textInputAction: TextInputAction.search,
          onChanged: _search.onTextChanged,
          onSubmitted: (_) => _search.submit(),
          maxLength: kSearchTextMaxCharacters,
          showCounter: false,
          helperText: _search.needsMoreLetters
              ? 'Tapez au moins 2 lettres'
              : null,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Effacer la recherche',
                  icon: const Icon(Icons.close),
                  onPressed: _clearSearch,
                ),
        ),
      ),
    );
  }

  Widget _buildFilterBar(ProviderProvider provider) {
    final count = _countLine();
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacingS),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
            // A12 — §21 row 68's finding #2, **device-confirmed**: this row
            // showed « RIGHT OVERFLOWED BY 122 PIXELS » on a 360×780pt iPhone
            // at ≈1.95×, because a `Row` handed the pill an unbounded width
            // and its own ellipsis never bound.
            //
            // **A `Wrap` now (consumer-search.md §2.5).** The count reads the
            // server's `total` — « 142 salons à Port-Bouët » — and a
            // `Row(spaceBetween)` would squeeze the pill under A12's
            // 8-character floor to fit it. In a `Wrap` the pill keeps the
            // whole row's width as its bound (so its ellipsis binds), the
            // count sits at the right when both fit, and moves to its own line
            // under the pill when they do not.
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppTheme.spacingS,
              children: [
                CommunePill(
                  commune: provider.selectedCommune,
                  onTap: () => _openCommunePicker(provider),
                ),
                if (count != null)
                  Text(
                    count,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          // §2.2 item 4: the home's strip; the chosen chip lit, « Tous »
          // when none. A tap narrows the same search in place.
          CategoryChips(
            selected: _search.category,
            onSelected: _search.selectCategory,
          ),
          const SizedBox(height: AppTheme.spacingXS),
          // **The view toggle lives here, not on the bar** (A15). It came off
          // the app bar because « Salons & Barbiers » cannot fit beside an
          // action at 1.34×, and it landed *beside the filter strip* rather
          // than in the commune row above because that row is already full: an
          // `IconButton` there squeezed « Toutes les communes » to 110.8dp and
          // reddened A12's 8-character floor. Here the strip is what gives, and
          // it gives by scrolling — which is what it already does.
          //
          // Outside the `SingleChildScrollView`, so a control over the results
          // cannot scroll out of reach.
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: AppTheme.spacingM),
                  child: Row(
                    children: [
                      _filterPill(
                        icon: Icons.swap_vert,
                        label: 'Trier',
                        active: _search.sort != ProviderSort.relevance,
                        onTap: _openSortSheet,
                      ),
                      const SizedBox(width: AppTheme.spacingS),
                      _filterPill(
                        icon: Icons.event_available,
                        label: 'Disponible aujourd’hui',
                        active: _search.availableToday,
                        onTap: () =>
                            _search.setAvailableToday(!_search.availableToday),
                      ),
                      const SizedBox(width: AppTheme.spacingS),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppTheme.spacingS),
                child: IconButton(
                  tooltip: _isGrid ? 'Afficher en liste' : 'Afficher en grille',
                  icon: Icon(_isGrid ? Icons.view_list : Icons.grid_view),
                  onPressed: () => setState(() => _isGrid = !_isGrid),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// « Trier » (lit while a sort other than relevance is on) and
  /// « Disponible aujourd'hui »: chips that say which is on — they were drawn
  /// by hand and said nothing of it to a screen reader (B9.8 F3).
  Widget _filterPill({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) => AppChip.choice(
    label: label,
    icon: icon,
    selected: active,
    onSelected: (_) => onTap(),
  );

  Future<void> _openSortSheet() async {
    final chosen = await showModalBottomSheet<ProviderSort>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLarge),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingL,
                AppTheme.spacingL,
                AppTheme.spacingL,
                AppTheme.spacingS,
              ),
              child: Text('Trier par', style: AppTextStyles.titleMedium),
            ),
            for (final option in ProviderSort.values)
              ListTile(
                title: Text(option.label),
                trailing: _search.sort == option
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, option),
              ),
            const SizedBox(height: AppTheme.spacingS),
          ],
        ),
      ),
    );
    if (chosen != null) await _search.setSort(chosen);
  }

  Widget _buildResults(ProviderProvider provider) {
    final empty = _emptyCopy(provider);
    return AppAsyncView<List<models.Provider>>(
      isLoading: _search.isLoading,
      // The list's own: [ProviderProvider.error] is a salon page's.
      error: _search.error,
      data: _search.items,
      isEmpty: (d) => d.isEmpty,
      loading: _isGrid
          ? const SkeletonCardList(block: true)
          : const SkeletonCardList(lead: SkeletonLead.thumbnail),
      empty: EmptyState(
        icon: empty.icon,
        title: empty.title,
        description: empty.description,
        actionText: empty.action,
        onAction: empty.onAction,
      ),
      onRetry: _search.refresh,
      onRefresh: _search.refresh,
      builder: (context, providers) => _results(providers),
    );
  }

  /// §2.10: one sentence, one way out — the most specific that holds,
  /// checked in order, and its action removes the narrowing it names.
  ///
  /// **First, is any salon public at all?** When the unfiltered featured
  /// read answered with nothing, « Vérifiez l’orthographe » or « Essayez une
  /// autre commune » would be false (A1's rule): the launch's production,
  /// where every salon is a draft.
  _EmptyCopy _emptyCopy(ProviderProvider provider) {
    const nothing = _EmptyCopy(
      icon: Icons.storefront_outlined,
      title: 'Aucun salon pour l’instant',
      description: 'Aucun salon n’accepte encore de réservations sur MyWeli.',
    );
    final shown = _search.shown;
    if (provider.noPublicSalon || shown == null) return nothing;
    final commune = shown.commune;
    if (shown.text.isNotEmpty) {
      return _EmptyCopy(
        icon: Icons.search_off,
        title: 'Aucun résultat pour « ${shown.text} »',
        description:
            'Vérifiez l’orthographe, ou cherchez une prestation : '
            '« tresses », « manucure »…',
        action: 'Effacer la recherche',
        onAction: _clearSearch,
      );
    }
    if (shown.availableToday) {
      return _EmptyCopy(
        icon: Icons.event_busy,
        title: 'Aucun salon disponible aujourd’hui',
        description: 'Les autres jours ont peut-être de la place.',
        action: 'Retirer ce filtre',
        onAction: () => _search.setAvailableToday(false),
      );
    }
    if (shown.category != null) {
      return _EmptyCopy(
        icon: Icons.search_off,
        title: commune != null
            ? 'Aucun salon dans cette catégorie à $commune'
            : 'Aucun salon dans cette catégorie',
        description: 'Essayez une autre catégorie.',
        action: 'Toutes les catégories',
        onAction: () => _search.selectCategory(null),
      );
    }
    if (commune != null) {
      return _EmptyCopy(
        icon: Icons.location_off_outlined,
        title: 'Aucun salon à $commune',
        description: 'Essayez une autre commune.',
        action: 'Voir toutes les communes',
        onAction: () => provider.setCommune(null),
      );
    }
    return nothing;
  }

  Widget _results(List<models.Provider> providers) {
    final footer = _footer();
    if (_isGrid) {
      return BrandRefresh(
        onRefresh: _search.refresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // A12 — **two columns is a claim about the text, not the screen.**
            // A 360dp phone's two-column cell is 156dp and gives the salon's
            // NAME 140 of it, which stops holding 8 characters at 1.90× — just
            // under the ≈1.95× contract point, so the device showed
            // « Salon … » and « Barber… » where a name should be. One column
            // is the same answer the dashboard's action grid takes above 1.3×.
            final inner = constraints.maxWidth - AppTheme.spacingM * 2;
            final twoColumnCell = (inner - AppTheme.spacingM) / 2;
            final columns =
                twoColumnCell >= ProviderCard.minGridCellWidth(context) ? 2 : 1;

            // A `CustomScrollView`, not a `GridView`: « Afficher plus » goes
            // after the grid, full width (§2.6), and a grid has no footer.
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(AppTheme.spacingM),
                  // `childAspectRatio: 0.75` derived tile HEIGHT from tile
                  // WIDTH, and width does not move with the OS text scale —
                  // so the card was 208dp at 100% and 208dp at 200%, with the
                  // text block clipped. The bound now comes from the card,
                  // which is the only thing that knows its own chrome (the
                  // same reason `carouselHeight` lives there). A full-width
                  // card has the room for the roomy design, so it gets the
                  // carousel's bound.
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: AppTheme.spacingM,
                      mainAxisSpacing: AppTheme.spacingM,
                      mainAxisExtent: columns == 1
                          ? ProviderCard.carouselHeight(context)
                          : ProviderCard.gridHeight(context),
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final p = providers[index];
                      return ProviderCard(
                        provider: p,
                        isGrid: true,
                        onTap: () => context.push('/provider/${p.id}'),
                      );
                    }, childCount: providers.length),
                  ),
                ),
                if (footer != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.spacingM,
                      0,
                      AppTheme.spacingM,
                      AppTheme.spacingM,
                    ),
                    sliver: SliverToBoxAdapter(child: footer),
                  ),
              ],
            );
          },
        ),
      );
    }

    return BrandRefresh(
      onRefresh: _search.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        itemCount: providers.length + (footer == null ? 0 : 1),
        itemBuilder: (context, index) {
          if (index == providers.length) return footer;
          final p = providers[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacingM),
            child: ProviderCard(
              provider: p,
              isGrid: false,
              onTap: () => context.push('/provider/${p.id}'),
            ),
          );
        },
      ),
    );
  }

  /// §2.6 — « Afficher plus de salons » while more exist: a loader in its
  /// place while the next page is out (the list stays), the failure and
  /// « Réessayer » there if it fails. Off while a new search is out: the
  /// next page belongs to one search.
  Widget? _footer() {
    if (!_search.hasMore) return null;
    final moreError = _search.moreError;
    if (moreError != null && !_search.isLoadingMore) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InlineFeedback('Impossible d’afficher la suite.'),
          const SizedBox(height: AppTheme.spacingS),
          AppButton(
            text: 'Réessayer',
            type: AppButtonType.secondary,
            onPressed: _search.canLoadMore ? _search.loadMore : null,
          ),
        ],
      );
    }
    return AppButton(
      text: 'Afficher plus de salons',
      type: AppButtonType.secondary,
      isLoading: _search.isLoadingMore,
      onPressed: _search.canLoadMore ? _search.loadMore : null,
    );
  }
}

/// One row of §2.10.
class _EmptyCopy {
  const _EmptyCopy({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? action;
  final VoidCallback? onAction;
}
