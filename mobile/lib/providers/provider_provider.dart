import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/di/dependency_injection.dart';
import '../models/provider.dart';
import '../models/review.dart';
import '../services/interfaces/provider_service_interface.dart';

class ProviderProvider extends ChangeNotifier {
  final ProviderServiceInterface _providerService =
      serviceLocator.providerService;

  List<Provider> _providers = [];
  List<Provider> _featuredProviders = [];
  Provider? _selectedProvider;
  bool _isLoading = false;
  String? _error;
  String? _selectedCategory;
  String? _selectedCommune;

  static const _communeKey = 'myweli_selected_commune_v1';

  List<Provider> get providers => _providers;
  List<Provider> get featuredProviders => _featuredProviders;
  Provider? get selectedProvider => _selectedProvider;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get selectedCategory => _selectedCategory;
  String? get selectedCommune => _selectedCommune;

  Future<void> loadProviders({
    String? category,
    String? searchQuery,
  }) async {
    _isLoading = true;
    _error = null;
    _selectedCategory = category;
    notifyListeners();

    try {
      final response = await _providerService.getProviders(
        category: category,
        searchQuery: searchQuery,
        commune: _selectedCommune,
      );
      if (response.success && response.data != null) {
        _providers = response.data!;
        _error = null;
      } else {
        _error = response.error ?? 'Erreur lors du chargement';
        _providers = [];
      }
    } catch (e) {
      _error = e.toString();
      _providers = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Restore the last selected commune from local storage (call at startup).
  Future<void> restoreSelectedCommune() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_communeKey);
    if (saved != null && saved.isNotEmpty) {
      _selectedCommune = saved;
      notifyListeners();
    }
  }

  /// Set the active commune (null = all communes), persist it, and reload the
  /// provider list for the current category.
  Future<void> setCommune(String? commune) async {
    _selectedCommune = (commune != null && commune.isNotEmpty) ? commune : null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (_selectedCommune == null) {
      await prefs.remove(_communeKey);
    } else {
      await prefs.setString(_communeKey, _selectedCommune!);
    }

    await loadProviders(category: _selectedCategory);
  }

  Future<void> loadFeaturedProviders() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _providerService.getFeaturedProviders();
      if (response.success && response.data != null) {
        _featuredProviders = response.data!;
      }
    } catch (e) {
      // Silent fail for featured providers
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadProviderById(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _providerService.getProviderById(id);
      if (response.success && response.data != null) {
        _selectedProvider = response.data;
        _error = null;
      } else {
        _error = response.error ?? 'Provider non trouvé';
        _selectedProvider = null;
      }
    } catch (e) {
      _error = e.toString();
      _selectedProvider = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearSelectedProvider() {
    _selectedProvider = null;
    notifyListeners();
  }

  void addReviewLocally(Review review) {
    if (_selectedProvider != null &&
        _selectedProvider!.id == review.providerId) {
      _selectedProvider = _selectedProvider!.copyWith(
        reviews: [..._selectedProvider!.reviews, review],
      );
      notifyListeners();
    }
  }
}
