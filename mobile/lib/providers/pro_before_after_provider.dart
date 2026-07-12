import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../models/before_after_pair.dart';
import '../services/interfaces/image_upload_service_interface.dart';
import '../services/interfaces/pro_service_interface.dart';

/// Manages a salon's before/after pairs (FR-DISC-006): load, add (two image
/// uploads via the pipeline) and remove, persisting through [ProServiceInterface].
/// Mirrors [ProGalleryProvider]. Design: docs/design/provider-before-after.md.
class ProBeforeAfterProvider extends ChangeNotifier implements SalonScoped {
  final ProServiceInterface _proService = serviceLocator.proService;
  final ImageUploadServiceInterface _uploadService =
      serviceLocator.imageUploadService;

  bool _isLoading = false;
  bool _loadFailed = false;
  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _error;
  List<BeforeAfterPair> _pairs = const [];

  bool get isLoading => _isLoading;
  bool get loadFailed => _loadFailed;
  bool get isUploading => _isUploading;
  double get uploadProgress => _uploadProgress;
  String? get error => _error;
  List<BeforeAfterPair> get pairs => _pairs;

  Future<void> load(String providerId) async {
    _isLoading = true;
    _loadFailed = false;
    _error = null;
    notifyListeners();
    try {
      final res = await _proService.getBeforeAfters(providerId);
      if (res.success && res.data != null) {
        _pairs = res.data!;
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

  /// Uploads the [beforeSource] + [afterSource] images, appends the pair, and
  /// persists. Returns false (with [error] set) on any failure.
  Future<bool> addPair(
    String providerId, {
    required String beforeSource,
    required String afterSource,
    String? caption,
  }) async {
    _isUploading = true;
    _uploadProgress = 0;
    _error = null;
    notifyListeners();
    try {
      final before = await _uploadService.uploadImage(
        source: beforeSource,
        onProgress: (p) {
          _uploadProgress = p * 0.5;
          notifyListeners();
        },
      );
      if (!before.success || before.data == null) {
        _error = before.error ?? 'Échec de l’envoi';
        return false;
      }
      final after = await _uploadService.uploadImage(
        source: afterSource,
        onProgress: (p) {
          _uploadProgress = 0.5 + p * 0.5;
          notifyListeners();
        },
      );
      if (!after.success || after.data == null) {
        _error = after.error ?? 'Échec de l’envoi';
        return false;
      }
      final trimmed = caption?.trim();
      final next = [
        ..._pairs,
        BeforeAfterPair(
          before: before.data!,
          after: after.data!,
          caption: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
        ),
      ];
      final saved = await _proService.updateBeforeAfters(providerId, next);
      if (saved.success && saved.data != null) {
        _pairs = saved.data!;
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

  Future<bool> removePair(String providerId, int index) async {
    if (index < 0 || index >= _pairs.length) return false;
    final next = [..._pairs]..removeAt(index);
    final saved = await _proService.updateBeforeAfters(providerId, next);
    if (saved.success && saved.data != null) {
      _pairs = saved.data!;
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
    _pairs = const [];
    notifyListeners();
  }
}
