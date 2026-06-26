import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../models/kyc_document.dart';
import '../models/provider_user.dart';
import '../services/interfaces/pro_kyc_service_interface.dart';

/// Holds the provider's KYC documents and verification status, and submits them
/// through [ProKycServiceInterface].
class ProKycProvider extends ChangeNotifier {
  final ProKycServiceInterface _service = serviceLocator.proKycService;

  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _loadFailed = false;
  String? _error;
  VerificationStatus _status = VerificationStatus.pending;
  String? _rejectionReason;
  KycDocumentType? _uploadingType;
  final Map<KycDocumentType, KycDocument> _documents = {};

  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  bool get loadFailed => _loadFailed;
  String? get error => _error;
  VerificationStatus get status => _status;
  String? get rejectionReason => _rejectionReason;

  /// The document type currently uploading (for a per-tile spinner), or null.
  KycDocumentType? get uploadingType => _uploadingType;
  Map<KycDocumentType, KycDocument> get documents =>
      Map.unmodifiable(_documents);

  KycDocument? documentFor(KycDocumentType type) => _documents[type];

  bool hasRequiredDocuments(BusinessType businessType) =>
      requiredKycDocuments(businessType).every(_documents.containsKey);

  /// Can submit when the required docs are present, the account isn't already
  /// verified, and no submit is in flight.
  bool canSubmit(BusinessType businessType) =>
      hasRequiredDocuments(businessType) &&
      _status != VerificationStatus.verified &&
      !_isSubmitting;

  Future<void> load(String providerUserId) async {
    _isLoading = true;
    _loadFailed = false;
    _error = null;
    notifyListeners();

    try {
      final res = await _service.getKycStatus(providerUserId);
      if (res.success && res.data != null) {
        _status = res.data!.status;
        _rejectionReason = res.data!.rejectionReason;
        _documents
          ..clear()
          ..addEntries(res.data!.documents.map((d) => MapEntry(d.type, d)));
        _loadFailed = false;
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

  /// Upload the picked file at [source] to private storage and record it for
  /// [type] (with its returned storage key). Returns false on failure.
  Future<bool> addDocument(
    KycDocumentType type,
    String source,
    String contentType,
  ) async {
    _uploadingType = type;
    _error = null;
    notifyListeners();
    try {
      final res = await _service.uploadDocument(
        source: source,
        contentType: contentType,
      );
      if (res.success && res.data != null) {
        _documents[type] = KycDocument(
          type: type,
          fileName: source.split('/').last,
          key: res.data!,
          submittedAt: DateTime.now(),
        );
        return true;
      }
      _error = res.error ?? 'Échec de l’envoi du document';
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _uploadingType = null;
      notifyListeners();
    }
  }

  void removeDocument(KycDocumentType type) {
    _documents.remove(type);
    notifyListeners();
  }

  Future<bool> submit(String providerUserId) async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final res = await _service.submitKyc(
        providerUserId: providerUserId,
        documents: _documents.values.toList(),
      );
      if (res.success && res.data != null) {
        _status = res.data!.status;
        _rejectionReason = res.data!.rejectionReason;
        _error = null;
        return true;
      }
      _error = res.error ?? "Erreur lors de l'envoi";
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
