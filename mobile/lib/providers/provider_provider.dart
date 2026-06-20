import 'package:flutter/foundation.dart';
import '../models/provider.dart';
import '../models/review.dart';
import '../core/di/dependency_injection.dart';
import '../services/interfaces/provider_service_interface.dart';

class ProviderProvider extends ChangeNotifier {
  final ProviderServiceInterface _providerService = serviceLocator.providerService;

  List<Provider> _providers = [];
  List<Provider> _featuredProviders = [];
  Provider? _selectedProvider;
  bool _isLoading = false;
  String? _error;
  String? _selectedCategory;

  List<Provider> get providers => _providers;
  List<Provider> get featuredProviders => _featuredProviders;
  Provider? get selectedProvider => _selectedProvider;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get selectedCategory => _selectedCategory;

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



