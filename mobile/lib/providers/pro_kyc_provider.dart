import 'package:flutter/foundation.dart';

import '../core/access/account_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/app_clock.dart';
import '../models/kyc_document.dart';
import '../models/provider_user.dart';
import '../services/interfaces/pro_kyc_service_interface.dart';

/// Holds the provider's KYC documents and verification status, and submits them
/// through [ProKycServiceInterface].
class ProKycProvider extends ChangeNotifier implements AccountScoped {
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

  /// What these fields hold is the server's, not the defaults they start
  /// with: a read has answered since the last reset (B9.8). The screen
  /// waits for it — on the first frame it showed the defaults.
  bool get loaded => _loaded;
  bool _loaded = false;
  String? get error => _error;
  VerificationStatus get status => _status;
  String? get rejectionReason => _rejectionReason;

  /// The document type currently uploading (for a per-tile spinner), or null.
  KycDocumentType? get uploadingType => _uploadingType;
  Map<KycDocumentType, KycDocument> get documents =>
      Map.unmodifiable(_documents);

  KycDocument? documentFor(KycDocumentType type) => _documents[type];

  /// The account changed (B9.14 — docs/design/pro-account-scope.md §2.1):
  /// these are the previous account's identity documents, its status and the
  /// reason a check was refused.
  /// Whose documents these are — moved by [resetForAccountChange]. A read,
  /// an upload or a submission sent before writes nothing when it answers
  /// after: A's document, landed after B signed in, would otherwise join B's
  /// set and go out with B's « Envoyer » (pro-account-scope.md §2.2).
  int _account = 0;

  @override
  void resetForAccountChange() {
    _account++;
    _documents.clear();
    _status = VerificationStatus.pending;
    _rejectionReason = null;
    _uploadingType = null;
    _loaded = false;
    _loadFailed = false;
    _isLoading = false;
    _isSubmitting = false;
    _error = null;
    notifyListeners();
  }

  bool hasRequiredDocuments(BusinessType businessType) =>
      requiredKycDocuments(businessType).every(_documents.containsKey);

  /// Can submit when the required docs are present, the account isn't already
  /// verified, and no submit is in flight.
  bool canSubmit(BusinessType businessType) =>
      hasRequiredDocuments(businessType) &&
      _status != VerificationStatus.verified &&
      !_isSubmitting;

  Future<void> load(String providerUserId) async {
    final account = _account;
    _isLoading = true;
    _loadFailed = false;
    _error = null;
    notifyListeners();

    try {
      final res = await _service.getKycStatus(providerUserId);
      if (account != _account) return;
      if (res.success && res.data != null) {
        _status = res.data!.status;
        _rejectionReason = res.data!.rejectionReason;
        _documents
          ..clear()
          ..addEntries(res.data!.documents.map((d) => MapEntry(d.type, d)));
        _loaded = true;
        _loadFailed = false;
      } else {
        _loadFailed = true;
        _error = res.error ?? kGenericErrorMessage;
      }
    } catch (e) {
      if (account != _account) return;
      _loadFailed = true;
      _error = kGenericErrorMessage;
    } finally {
      if (account == _account) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Upload the picked file at [source] to private storage and record it for
  /// [type] (with its returned storage key). Returns false on failure.
  Future<bool> addDocument(
    KycDocumentType type,
    String source,
    String contentType,
  ) async {
    final account = _account;
    _uploadingType = type;
    _error = null;
    notifyListeners();
    try {
      final res = await _service.uploadDocument(
        source: source,
        contentType: contentType,
      );
      if (account != _account) return false;
      if (res.success && res.data != null) {
        _documents[type] = KycDocument(
          type: type,
          fileName: source.split('/').last,
          key: res.data!,
          submittedAt: AppClock.now(),
        );
        return true;
      }
      _error = res.error ?? 'Échec de l’envoi du document';
      return false;
    } catch (e) {
      if (account != _account) return false;
      _error = kGenericErrorMessage;
      return false;
    } finally {
      if (account == _account) {
        _uploadingType = null;
        notifyListeners();
      }
    }
  }

  void removeDocument(KycDocumentType type) {
    _documents.remove(type);
    notifyListeners();
  }

  Future<bool> submit(String providerUserId) async {
    final account = _account;
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final res = await _service.submitKyc(
        providerUserId: providerUserId,
        documents: _documents.values.toList(),
      );
      if (account != _account) return res.success;
      if (res.success && res.data != null) {
        _status = res.data!.status;
        _rejectionReason = res.data!.rejectionReason;
        _error = null;
        return true;
      }
      _error = res.error ?? 'Erreur lors de l’envoi';
      return false;
    } catch (e) {
      if (account != _account) return false;
      _error = kGenericErrorMessage;
      return false;
    } finally {
      if (account == _account) {
        _isSubmitting = false;
        notifyListeners();
      }
    }
  }
}
