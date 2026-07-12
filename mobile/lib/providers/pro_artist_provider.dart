import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../models/artist.dart';
import '../services/interfaces/image_upload_service_interface.dart';
import '../services/interfaces/pro_artist_service_interface.dart';

class ProArtistProvider extends ChangeNotifier implements SalonScoped {
  final ProArtistServiceInterface _artistService =
      serviceLocator.proArtistService;
  final ImageUploadServiceInterface _uploadService =
      serviceLocator.imageUploadService;

  List<Artist> _artists = [];
  bool _isLoading = false;
  bool _isUploadingAvatar = false;
  double _avatarProgress = 0;
  String? _error;

  List<Artist> get artists => _artists;
  bool get isLoading => _isLoading;
  bool get isUploadingAvatar => _isUploadingAvatar;
  double get avatarProgress => _avatarProgress;
  String? get error => _error;

  /// Uploads a staff photo through the image pipeline; returns the hosted URL.
  Future<String?> uploadAvatar(String source) async {
    _isUploadingAvatar = true;
    _avatarProgress = 0;
    notifyListeners();
    try {
      final res = await _uploadService.uploadImage(
        source: source,
        onProgress: (p) {
          _avatarProgress = p;
          notifyListeners();
        },
      );
      if (res.success && res.data != null) return res.data;
      _error = res.error ?? 'Échec de l’envoi';
      return null;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isUploadingAvatar = false;
      notifyListeners();
    }
  }

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

  /// R6 multi-salons: drop the previous salon's data on a switch.
  @override
  void resetForSalonSwitch() {
    _artists = [];
    _isLoading = false;
    _isUploadingAvatar = false;
    _avatarProgress = 0;
    _error = null;
    notifyListeners();
  }
}
