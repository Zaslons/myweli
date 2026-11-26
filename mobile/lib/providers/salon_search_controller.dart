import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/salon_figures.dart';
import '../core/utils/salon_id.dart';
import '../core/utils/search_text.dart';
import '../models/api_response.dart';
import '../models/provider.dart';
import '../models/provider_page.dart';
import '../services/interfaces/provider_service_interface.dart';
import 'provider_provider.dart';

/// How long the field waits after the last key before it searches (§2.3).
const kSearchDebounce = Duration(milliseconds: 350);

/// The salon list's own search (docs/design/consumer-search.md §2.3, §2.6,
/// §2.7, §5): created with `ProviderListScreen`, disposed with it.
///
/// **Its own state, not [ProviderProvider]'s.** The list, the home and the
/// map shared one list and one category: a category tapped here came back as
/// the home's « Près de vous », and the map reset it. Here live the text, the
/// category, the sort and « Disponible aujourd’hui » (remembered on
/// [ProviderProvider] for the session, decision 236), the pages, and the
/// flags — none of which any other screen reads.
///
/// **The commune stays shared** ([ProviderProvider.selectedCommune]). This
/// controller listens, and searches again only when it actually changed:
/// [ProviderProvider] notifies on every salon read, and a list going back to
/// page 1 each time a salon is opened from it would lose the person's place.
///
/// **Only the latest search writes the list.** Each read carries a number
/// (the slot picker's `_reqId`); an answer for an older one is dropped, a
/// page of « Afficher plus » included.
class SalonSearchController extends ChangeNotifier implements SalonCopyHolder {
  SalonSearchController({
    required ProviderProvider providers,
    ProviderServiceInterface? service,
    this._category,
    this.debounce = kSearchDebounce,
  }) : _providers = providers,
       _service = service ?? serviceLocator.providerService,
       _sort = providers.listSort,
       _availableToday = providers.listAvailableToday,
       _commune = providers.selectedCommune {
    providers
      ..attachSalonHolder(this)
      ..addListener(_onProviders);
    unawaited(_search(''));
  }

  final ProviderProvider _providers;
  final ProviderServiceInterface _service;
  final Duration debounce;

  /// The field's text, cleaned as it would be sent.
  String _fieldText = '';
  String? _category;
  ProviderSort _sort;
  bool _availableToday;

  /// The commune the last search was started with.
  String? _commune;

  /// The search the results on screen answer (or, failed, the one that
  /// failed). Null before the first answer.
  ProviderQuery? _shown;
  List<Provider>? _items;
  int _total = 0;
  int _page = 0;
  int _pageSize = kSalonPageSize;

  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  String? _moreError;
  int _req = 0;
  int _answers = 0;
  Timer? _timer;
  bool _disposed = false;

  /// The salons shown; null until the first answer.
  List<Provider>? get items => _items;

  /// Every salon the shown search matches (the server's `total`).
  int get total => _total;

  /// The search the results answer: its text, category, commune and filters
  /// word the count and the empty state.
  ProviderQuery? get shown => _shown;
  String? get category => _category;
  ProviderSort get sort => _sort;
  bool get availableToday => _availableToday;

  /// A first page is out — the first search, or a new one.
  bool get isLoading => _isLoading;

  /// A new search is out over an answer still shown — salons, or an empty
  /// answer's sentence: it stays, and the count line says « Recherche… »
  /// (§2.3). Not over the error view: « Réessayer » brings the skeleton back.
  bool get isSearchingAgain {
    final items = _items;
    return _isLoading && items != null && (items.isNotEmpty || _error == null);
  }

  bool get isLoadingMore => _isLoadingMore;

  /// The first page failed. **It stays until the next answer** — cleared at
  /// the start of a search, the error view gave way to an empty list for a
  /// frame, then to the skeleton.
  String? get error => _error;

  /// The next page failed; the salons shown stay (§2.6).
  String? get moreError => _moreError;

  /// More salons than shown (§2.6: `page × 20 < total`).
  bool get hasMore => _items != null && _page * _pageSize < _total;

  /// « Afficher plus » belongs to one search: off while a new one is out.
  bool get canLoadMore => hasMore && !_isLoading && !_isLoadingMore;

  /// The field holds fewer characters than a search needs, and more than
  /// none: « Tapez au moins 2 lettres », and nothing is asked (§2.3).
  bool get needsMoreLetters {
    final n = searchTextLength(_fieldText);
    return n > 0 && n < kSearchMinCharacters;
  }

  /// How many first pages have answered — the screen announces each answer
  /// once (§2.5), not each key.
  int get answers => _answers;

  /// The field changed: search 350 ms after the last key, from 2 letters; an
  /// emptied field searches at once without text (§2.3).
  void onTextChanged(String raw) {
    _fieldText = cleanSearchText(raw);
    _timer?.cancel();
    final n = searchTextLength(_fieldText);
    if (n == 0) {
      if (_searchedText.isNotEmpty) {
        unawaited(_search(''));
        return;
      }
    } else if (n >= kSearchMinCharacters && _fieldText != _searchedText) {
      _timer = Timer(debounce, () => unawaited(_search(_fieldText)));
    }
    notifyListeners();
  }

  /// The keyboard's « Rechercher »: at once, no wait. Below 2 letters it does
  /// nothing — the helper line already says why.
  Future<void> submit() async {
    if (needsMoreLetters) return;
    await _search(_fieldText);
  }

  /// A chip (§2.4): [key] narrows the same search; the lit chip again, or
  /// null (« Tous »), removes the category.
  Future<void> selectCategory(String? key) async {
    _category = (key == null || key == _category) ? null : key;
    await _search(_textToSearch);
  }

  Future<void> setSort(ProviderSort sort) async {
    if (sort == _sort) return;
    _sort = sort;
    _remember();
    await _search(_textToSearch);
  }

  Future<void> setAvailableToday(bool value) async {
    if (value == _availableToday) return;
    _availableToday = value;
    _remember();
    await _search(_textToSearch);
  }

  /// A pull to refresh, or « Réessayer »: page 1 again, of the field's text
  /// — a pull during the 350 ms wait cancels the wait (§2.3).
  Future<void> refresh() => _search(_textToSearch);

  /// « Afficher plus de salons » (§2.6): the next page, appended without
  /// the salons already shown. A failure keeps them and says so.
  Future<void> loadMore() async {
    final shown = _shown;
    if (!canLoadMore || shown == null) return;
    final req = _req;
    _isLoadingMore = true;
    _moreError = null;
    notifyListeners();

    final res = await _ask(
      ProviderQuery(
        text: shown.text,
        category: shown.category,
        commune: shown.commune,
        sort: shown.sort,
        availableToday: shown.availableToday,
        page: _page + 1,
      ),
    );
    // A new search started while this page was out: it is not that
    // search's page (§2.6, « belongs to one search »).
    if (_disposed || req != _req) return;
    final page = res.data;
    if (res.success && page != null) {
      final seen = {for (final p in _items ?? const <Provider>[]) p.id};
      _items = [
        ...?_items,
        for (final p in page.items)
          if (seen.add(p.id)) p,
      ];
      _page = page.page;
      _pageSize = page.pageSize;
      _total = page.total;
    } else {
      _moreError = res.error ?? kGenericErrorMessage;
    }
    _isLoadingMore = false;
    notifyListeners();
  }

  /// The text a search started now would send: the field's, unless it is
  /// below the floor — then the one already searched.
  String get _textToSearch => needsMoreLetters ? _searchedText : _fieldText;

  /// The text of the search shown, or of the one out.
  String get _searchedText => _pending?.text ?? _shown?.text ?? '';
  ProviderQuery? _pending;

  Future<void> _search(String text) async {
    _timer?.cancel();
    final req = ++_req;
    final query = ProviderQuery(
      text: text,
      category: _category,
      commune: _commune,
      sort: _sort,
      availableToday: _availableToday,
    );
    _pending = query;
    _isLoading = true;
    _isLoadingMore = false;
    _moreError = null;
    notifyListeners();

    final res = await _ask(query);
    if (_disposed || req != _req) return;
    _pending = null;
    final page = res.data;
    if (res.success && page != null) {
      final seen = <SalonId>{};
      _items = [
        for (final p in page.items)
          if (seen.add(p.id)) p,
      ];
      _page = page.page;
      _pageSize = page.pageSize;
      _total = page.total;
      _error = null;
    } else {
      _error = res.error ?? kGenericErrorMessage;
      // The same search pulled again keeps what was shown (SYSTEM §12.1). A
      // NEW search that failed must not leave the previous one's salons
      // under it: they would answer a text the person no longer reads.
      if (query != _shown) {
        _items = const [];
        _total = 0;
        _page = 0;
      }
    }
    _shown = query;
    _isLoading = false;
    _answers++;
    notifyListeners();
  }

  Future<ApiResponse<ProviderPage>> _ask(ProviderQuery query) async {
    try {
      return await _service.searchProviders(query);
    } catch (_) {
      return ApiResponse.error(kGenericErrorMessage);
    }
  }

  void _remember() => _providers.rememberListFilters(
    sort: _sort,
    availableToday: _availableToday,
  );

  /// The shared commune changed — and only then (§2.7): search again, the
  /// text kept.
  void _onProviders() {
    final commune = _providers.selectedCommune;
    if (commune == _commune) return;
    _commune = commune;
    unawaited(_search(_textToSearch));
  }

  @override
  Provider? heldSalon(SalonId id) {
    for (final p in _items ?? const <Provider>[]) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  void patchSalonFigures(
    SalonId id, {
    required double rating,
    required int reviewCount,
  }) {
    final items = _items;
    if (_disposed || items == null) return;
    _items = withSalonFigures(
      items,
      id,
      rating: rating,
      reviewCount: reviewCount,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _providers
      ..removeListener(_onProviders)
      ..detachSalonHolder(this);
    super.dispose();
  }
}
