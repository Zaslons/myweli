import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../services/interfaces/image_upload_service_interface.dart';
import '../services/interfaces/pro_service_interface.dart';

/// Manages a provider's salon gallery photos: load, upload (via the image
/// pipeline) and remove, persisting through [ProServiceInterface].
class ProGalleryProvider extends ChangeNotifier implements SalonScoped {
  final ProServiceInterface _proService = serviceLocator.proService;
  final ImageUploadServiceInterface _uploadService =
      serviceLocator.imageUploadService;

  bool _isLoading = false;
  bool _loadFailed = false;
  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _error;
  List<String> _photos = const [];

  bool get isLoading => _isLoading;
  bool get loadFailed => _loadFailed;
  bool get isUploading => _isUploading;
  double get uploadProgress => _uploadProgress;
  String? get error => _error;
  List<String> get photos => _photos;

  Future<void> load(String providerId) async {
    _isLoading = true;
    _loadFailed = false;
    _error = null;
    notifyListeners();
    try {
      final res = await _proService.getGalleryPhotos(providerId);
      if (res.success && res.data != null) {
        _photos = res.data!;
      } else {
        _loadFailed = true;
        _error = res.error ?? 'Erreur lors du chargement';
      }
    } catch (e) {
      _loadFailed = true;
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addPhoto(String providerId, String source) async {
    _isUploading = true;
    _uploadProgress = 0;
    _error = null;
    notifyListeners();
    try {
      final upload = await _uploadService.uploadImage(
        source: source,
        onProgress: (p) {
          _uploadProgress = p;
          notifyListeners();
        },
      );
      if (!upload.success || upload.data == null) {
        _error = upload.error ?? 'Échec de l’envoi';
        return false;
      }
      final next = [..._photos, upload.data!];
      final saved = await _proService.updateGalleryPhotos(providerId, next);
      if (saved.success && saved.data != null) {
        _photos = saved.data!;
        return true;
      }
      _error = saved.error ?? 'Échec de l’enregistrement';
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  /// Reorder (audit 3.6 — the first photo is the listing cover): swap the
  /// photo with its neighbour and persist through the same gallery PUT.
  Future<bool> movePhoto(String providerId, int index, int delta) async {
    final target = index + delta;
    if (index < 0 ||
        index >= _photos.length ||
        target < 0 ||
        target >= _photos.length) {
      return false;
    }
    final next = [..._photos];
    final tmp = next[index];
    next[index] = next[target];
    next[target] = tmp;
    final saved = await _proService.updateGalleryPhotos(providerId, next);
    if (saved.success && saved.data != null) {
      _photos = saved.data!;
      _error = null;
      notifyListeners();
      return true;
    }
    _error = saved.error ?? 'Échec du déplacement';
    notifyListeners();
    return false;
  }

  Future<bool> removePhoto(String providerId, int index) async {
    if (index < 0 || index >= _photos.length) return false;
    final next = [..._photos]..removeAt(index);
    final saved = await _proService.updateGalleryPhotos(providerId, next);
    if (saved.success && saved.data != null) {
      _photos = saved.data!;
      _error = null;
      notifyListeners();
      return true;
    }
    _error = saved.error ?? 'Échec de la suppression';
    notifyListeners();
    return false;
  }

  /// R6 multi-salons: drop the previous salon's data on a switch.
  @override
  void resetForSalonSwitch() {
    _isLoading = false;
    _loadFailed = false;
    _isUploading = false;
    _uploadProgress = 0;
    _error = null;
    _photos = const [];
    notifyListeners();
  }
}
