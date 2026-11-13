import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/gallery_batch.dart';
import '../core/utils/salon_id.dart';
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

  /// What these fields hold is the server's, not the defaults they start
  /// with: a read has answered since the last reset (B9.8). The screen
  /// waits for it — on the first frame it showed the defaults.
  bool get loaded => _loaded;
  bool _loaded = false;

  /// True from the first photo of a pick to the last — between two photos of a
  /// batch too, so the add tile never comes back mid-way.
  bool get isUploading => _isUploading || _inBatch;
  double get uploadProgress => _uploadProgress;

  /// Where a pick of several stands — « Envoi 2 sur 5… »; (0, 0) otherwise.
  int get batchAt => _batchAt;
  int get batchOf => _batchOf;
  bool _inBatch = false;
  bool _stopBatch = false;
  int _batchAt = 0;
  int _batchOf = 0;
  String? get error => _error;
  List<String> get photos => _photos;

  Future<void> load(SalonId providerId) async {
    final scope = _scope;
    _isLoading = true;
    _loadFailed = false;
    _error = null;
    notifyListeners();
    try {
      final res = await _proService.getGalleryPhotos(providerId);
      if (scope != _scope) return;
      if (res.success && res.data != null) {
        _photos = res.data!;
        _loaded = true;
      } else {
        _loadFailed = true;
        _error = res.error ?? kGenericErrorMessage;
      }
    } catch (e) {
      if (scope != _scope) return;
      _loadFailed = true;
      _error = kGenericErrorMessage;
    } finally {
      if (scope == _scope) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> addPhoto(SalonId providerId, String source) async {
    final scope = _scope;
    _isUploading = true;
    _uploadProgress = 0;
    _error = null;
    notifyListeners();
    try {
      final upload = await _uploadService.uploadImage(
        source: source,
        onProgress: (p) {
          if (scope != _scope) return;
          _uploadProgress = p;
          notifyListeners();
        },
      );
      if (scope != _scope) return false;
      if (!upload.success || upload.data == null) {
        _error = upload.error ?? 'Échec de l’envoi';
        return false;
      }
      final next = [..._photos, upload.data!];
      final saved = await _proService.updateGalleryPhotos(providerId, next);
      if (scope != _scope) return saved.success;
      if (saved.success && saved.data != null) {
        _photos = saved.data!;
        return true;
      }
      _error = saved.error ?? 'Échec de l’enregistrement';
      return false;
    } catch (e) {
      if (scope != _scope) return false;
      _error = kGenericErrorMessage;
      return false;
    } finally {
      if (scope == _scope) {
        _isUploading = false;
        notifyListeners();
      }
    }
  }

  /// Several photos picked at once (docs/design/gallery-multi-select.md): the
  /// first ones up to the room left under [kMaxGalleryPhotos], ONE AFTER
  /// ANOTHER through [addPhoto] — the same upload and the same save, so each
  /// photo is kept at the address the server stored and shows as it lands.
  /// One at a time because each is decoded and compressed on the phone, and
  /// several at once is how a 2–3 GB Android runs out of memory.
  ///
  /// Stops before the next photo when [stopBatch] is called (the screen was
  /// left) or the salon changes; the photo on its way finishes, as a single
  /// add always has.
  Future<({int total, int added, int dropped, bool stopped})> addPhotos(
    SalonId providerId,
    List<String> sources,
  ) async {
    final scope = _scope;
    final fit = fitInGallery(sources, _photos.length);
    _inBatch = true;
    _stopBatch = false;
    _batchOf = fit.kept.length;
    _batchAt = 0;
    var added = 0;
    var stopped = false;
    try {
      for (final source in fit.kept) {
        if (_stopBatch || scope != _scope) {
          stopped = true;
          break;
        }
        _batchAt++;
        notifyListeners();
        if (await addPhoto(providerId, source)) added++;
      }
    } finally {
      if (scope == _scope) {
        _inBatch = false;
        _batchAt = 0;
        _batchOf = 0;
        notifyListeners();
      }
    }
    return (
      total: fit.kept.length,
      added: added,
      dropped: fit.dropped,
      stopped: stopped || scope != _scope,
    );
  }

  /// The screen was left: the photo on its way finishes; the rest of the pick
  /// is not sent.
  void stopBatch() => _stopBatch = true;

  /// Reorder (audit 3.6 — the first photo is the listing cover): swap the
  /// photo with its neighbour and persist through the same gallery PUT.
  Future<bool> movePhoto(SalonId providerId, int index, int delta) async {
    final scope = _scope;
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
    if (scope != _scope) return saved.success;
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

  /// « Définir comme photo principale » (gallery-set-cover.md): the photo
  /// jumps to index 0 — ONE wholesale PUT instead of `index` arrow taps.
  /// Derives from the CURRENT list at call time, never a captured one — the
  /// [restorePhotoAt] rule.
  Future<bool> setCover(SalonId providerId, int index) async {
    final scope = _scope;
    // 0 is already the cover; nothing to write.
    if (index <= 0 || index >= _photos.length) return false;
    final next = [..._photos];
    next.insert(0, next.removeAt(index));
    final saved = await _proService.updateGalleryPhotos(providerId, next);
    if (scope != _scope) return saved.success;
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

  /// A6/§15: put ONE photo back where it was — the Undo behind the delete
  /// confirmation.
  ///
  /// It re-inserts into the CURRENT list rather than PUTting the pre-delete
  /// snapshot. The review caught that: the service takes the whole list, so
  /// restoring a snapshot silently reverts anything done during the 10s undo
  /// window — a reorder, or worse, a photo uploaded in the meantime, destroyed
  /// with no warning. Undo must undo one action, not rewind the gallery.
  Future<bool> restorePhotoAt(SalonId providerId, int index, String url) async {
    final scope = _scope;
    final next = [..._photos];
    next.insert(index.clamp(0, next.length), url);
    final saved = await _proService.updateGalleryPhotos(providerId, next);
    if (scope != _scope) return saved.success;
    if (saved.success && saved.data != null) {
      _photos = saved.data!;
      _error = null;
      notifyListeners();
      return true;
    }
    _error = saved.error ?? 'Restauration impossible';
    notifyListeners();
    return false;
  }

  Future<bool> removePhoto(SalonId providerId, int index) async {
    final scope = _scope;
    if (index < 0 || index >= _photos.length) return false;
    final next = [..._photos]..removeAt(index);
    final saved = await _proService.updateGalleryPhotos(providerId, next);
    if (scope != _scope) return saved.success;
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
  /// Which salon this state belongs to — moved by [resetForSalonSwitch]
  /// only. A read or a write takes it before it awaits and writes nothing
  /// when it moved meanwhile: its answer is the previous salon's, or the
  /// previous account's (docs/design/pro-account-scope.md §2.2).
  int _scope = 0;

  @override
  void resetForSalonSwitch() {
    _scope++;
    _loaded = false;
    _isLoading = false;
    _loadFailed = false;
    _isUploading = false;
    _uploadProgress = 0;
    _inBatch = false;
    _stopBatch = true;
    _batchAt = 0;
    _batchOf = 0;
    _error = null;
    _photos = const [];
    notifyListeners();
  }
}
