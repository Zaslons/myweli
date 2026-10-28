import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/salon_id.dart';
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

  /// The load's own failure: [error] is also every write's here, so a failed
  /// save would read as the list's load error (B9.8).
  String? get loadError => _loadError;
  String? _loadError;

  /// Uploads a staff photo through the image pipeline; returns the hosted URL.
  Future<String?> uploadAvatar(String source) async {
    final scope = _scope;
    _isUploadingAvatar = true;
    _avatarProgress = 0;
    notifyListeners();
    try {
      final res = await _uploadService.uploadImage(
        source: source,
        onProgress: (p) {
          if (scope != _scope) return;
          _avatarProgress = p;
          notifyListeners();
        },
      );
      if (scope != _scope) return null;
      if (res.success && res.data != null) return res.data;
      _error = res.error ?? 'Échec de l’envoi';
      return null;
    } catch (e) {
      if (scope != _scope) return null;
      _error = kGenericErrorMessage;
      return null;
    } finally {
      if (scope == _scope) {
        _isUploadingAvatar = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadArtists(SalonId providerId) async {
    final scope = _scope;
    _isLoading = true;
    _error = null;
    _loadError = null;
    notifyListeners();

    try {
      final response = await _artistService.getArtists(providerId);
      if (scope != _scope) return;
      if (response.success && response.data != null) {
        _artists = response.data!;
        _error = null;
      } else {
        _error = response.error ?? 'Erreur lors du chargement des artistes';
        _loadError = _error;
        _artists = [];
      }
    } catch (e) {
      if (scope != _scope) return;
      _error = kGenericErrorMessage;
      _loadError = _error;
      _artists = [];
    } finally {
      if (scope == _scope) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> createArtist(
    SalonId providerId,
    Map<String, dynamic> data,
  ) async {
    final scope = _scope;
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _artistService.createArtist(providerId, data);
      if (scope != _scope) return response.success;
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
      if (scope != _scope) return false;
      _error = kGenericErrorMessage;
      notifyListeners();
      return false;
    } finally {
      if (scope == _scope) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> updateArtist(String artistId, Map<String, dynamic> data) async {
    final scope = _scope;
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _artistService.updateArtist(artistId, data);
      if (scope != _scope) return response.success;
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
      if (scope != _scope) return false;
      _error = kGenericErrorMessage;
      notifyListeners();
      return false;
    } finally {
      if (scope == _scope) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> deleteArtist(String artistId) async {
    final scope = _scope;
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _artistService.deleteArtist(artistId);
      if (scope != _scope) return response.success;
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
      if (scope != _scope) return false;
      _error = kGenericErrorMessage;
      notifyListeners();
      return false;
    } finally {
      if (scope == _scope) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// R6 multi-salons: drop the previous salon's data on a switch.
  /// Which salon this state belongs to — moved by [resetForSalonSwitch]
  /// only. A read or a write takes it before it awaits and writes nothing
  /// when it moved meanwhile: its answer is the previous salon's, or the
  /// previous account's (docs/design/pro-account-scope.md §2.2).
  int _scope = 0;

  @override
  void resetForSalonSwitch() {
    _scope++;
    _loadError = null;
    _artists = [];
    _isLoading = false;
    _isUploadingAvatar = false;
    _avatarProgress = 0;
    _error = null;
    notifyListeners();
  }
}
