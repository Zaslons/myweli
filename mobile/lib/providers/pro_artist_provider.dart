import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../models/artist.dart';
import '../services/interfaces/pro_artist_service_interface.dart';

class ProArtistProvider extends ChangeNotifier {
  final ProArtistServiceInterface _artistService =
      serviceLocator.proArtistService;

  List<Artist> _artists = [];
  bool _isLoading = false;
  String? _error;

  List<Artist> get artists => _artists;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadArtists(String providerId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _artistService.getArtists(providerId);
      if (response.success && response.data != null) {
        _artists = response.data!;
        _error = null;
      } else {
        _error = response.error ?? 'Erreur lors du chargement des artistes';
        _artists = [];
      }
    } catch (e) {
      _error = e.toString();
      _artists = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createArtist(
      String providerId, Map<String, dynamic> data) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _artistService.createArtist(providerId, data);
      if (response.success && response.data != null) {
        _artists.add(response.data!);
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de la création';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateArtist(String artistId, Map<String, dynamic> data) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _artistService.updateArtist(artistId, data);
      if (response.success && response.data != null) {
        final index = _artists.indexWhere((a) => a.id == artistId);
        if (index != -1) {
          _artists[index] = response.data!;
        }
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de la mise à jour';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteArtist(String artistId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _artistService.deleteArtist(artistId);
      if (response.success) {
        _artists.removeWhere((a) => a.id == artistId);
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de la suppression';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
