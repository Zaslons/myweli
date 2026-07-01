import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../models/kyc_document.dart';
import '../../../models/provider_user.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_kyc_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';

class ProKycScreen extends StatefulWidget {
  const ProKycScreen({super.key});

  @override
  State<ProKycScreen> createState() => _ProKycScreenState();
}

class _ProKycScreenState extends State<ProKycScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pro = context.read<ProAuthProvider>().provider;
      if (pro != null) {
        context.read<ProKycProvider>().load(pro.id);
      }
    });
  }

  Future<void> _submit(ProviderUser pro, ProKycProvider kyc) async {
    final ok = await kyc.submit(pro.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Documents soumis pour vérification' : (kyc.error ?? 'Erreur'),
        ),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Vérification')),
      body: Consumer2<ProAuthProvider, ProKycProvider>(
        builder: (context, auth, kyc, _) {
          final pro = auth.provider;
          if (pro == null) {
            return const Center(child: Text('Veuillez vous connecter'));
          }
          if (kyc.isLoading) {
            return const LoadingIndicator();
          }
          if (kyc.loadFailed) {
            return EmptyState(
              icon: Icons.wifi_off,
              title: 'Chargement impossible',
              description: 'Vérifiez votre connexion et réessayez.',
              actionText: 'Réessayer',
              onAction: () => kyc.load(pro.id),
            );
          }
          return _buildForm(pro, kyc);
        },
      ),
    );
  }

  Widget _buildForm(ProviderUser pro, ProKycProvider kyc) {
    final verified = kyc.status == VerificationStatus.verified;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      children: [
        _StatusBanner(status: kyc.status, rejectionReason: kyc.rejectionReason),
        const SizedBox(height: AppTheme.spacingL),
        Text(
          'DOCUMENTS',
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        for (final type in KycDocumentType.values) ...[
          _DocumentTile(
            type: type,
            required: isKycDocumentRequired(type, pro.businessType),
            document: kyc.documentFor(type),
            readOnly: verified,
            uploading: kyc.uploadingType == type,
            onAdd: () => _provideDoc(context, kyc, type),
            onRemove: () => kyc.removeDocument(type),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_outline,
                size: 16, color: AppColors.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Les acomptes sont activés une fois votre compte vérifié. '
                'Vos documents sont chiffrés et confidentiels.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
        if (!verified) ...[
          const SizedBox(height: AppTheme.spacingL),
          AppButton(
            text: 'Soumettre pour vérification',
            isLoading: kyc.isSubmitting,
            onPressed: kyc.canSubmit(pro.businessType)
                ? () => _submit(pro, kyc)
                : null,
          ),
          if (!kyc.hasRequiredDocuments(pro.businessType)) ...[
            const SizedBox(height: 8),
            Text(
              'Ajoutez les documents requis pour soumettre.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// Pick a document (image or PDF) and upload it. In demo (mock) mode the
  /// sample filename is used so the flow works without a device file.
  Future<void> _provideDoc(
    BuildContext context,
    ProKycProvider kyc,
    KycDocumentType type,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final String source;
    final String contentType;
    if (AppConfig.useApiBackend) {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      );
      final path = picked?.files.single.path;
      if (path == null) return;
      source = path;
      contentType = _contentTypeFor(path);
    } else {
      source = _mockFileName(type);
      contentType = 'image/jpeg';
    }
    final ok = await kyc.addDocument(type, source, contentType);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(kyc.error ?? 'Échec de l’envoi du document'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _contentTypeFor(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }

  String _mockFileName(KycDocumentType type) {
    switch (type) {
      case KycDocumentType.idCard:
        return 'piece_identite.jpg';
      case KycDocumentType.selfie:
        return 'photo_visage.jpg';
      case KycDocumentType.businessRegistration:
        return 'rccm.jpg';
      case KycDocumentType.addressProof:
        return 'justificatif_adresse.jpg';
    }
  }
}

class _StatusBanner extends StatelessWidget {
  final VerificationStatus status;
  final String? rejectionReason;

  const _StatusBanner({required this.status, this.rejectionReason});

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final IconData icon;
    late final String title;
    late final String subtitle;

    switch (status) {
      case VerificationStatus.pending:
        color = AppColors.warning;
        icon = Icons.schedule;
        title = 'Vérification en attente';
        subtitle = 'Soumettez vos documents pour être vérifié.';
        break;
      case VerificationStatus.verified:
        color = AppColors.success;
        icon = Icons.verified;
        title = 'Compte vérifié';
        subtitle = 'Vous pouvez activer les acomptes.';
        break;
      case VerificationStatus.rejected:
        color = AppColors.error;
        icon = Icons.error_outline;
        title = 'Vérification refusée';
        subtitle = rejectionReason ?? 'Veuillez renvoyer vos documents.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleSmall.copyWith(color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall.copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final KycDocumentType type;
  final bool required;
  final KycDocument? document;
  final bool readOnly;
  final bool uploading;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _DocumentTile({
    required this.type,
    required this.required,
    required this.document,
    required this.readOnly,
    required this.uploading,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final provided = document != null;
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(_icon(type), size: 22, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label(type) + (required ? '' : ' (optionnel)'),
                  style: AppTextStyles.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  provided ? 'Fourni · ${document!.fileName}' : 'À fournir',
                  style: AppTextStyles.bodySmall.copyWith(
                    color:
                        provided ? AppColors.success : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (uploading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: BrandLoader(size: 20, fast: true),
              ),
            )
          else if (!readOnly) ...[
            if (provided)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: AppColors.textTertiary,
                onPressed: onRemove,
                tooltip: 'Retirer',
              ),
            TextButton(
              onPressed: onAdd,
              child: Text(provided ? 'Modifier' : 'Ajouter'),
            ),
          ],
        ],
      ),
    );
  }

  String _label(KycDocumentType type) {
    switch (type) {
      case KycDocumentType.idCard:
        return 'Pièce d\'identité (CNI / passeport)';
      case KycDocumentType.selfie:
        return 'Photo du visage';
      case KycDocumentType.businessRegistration:
        return 'Registre de commerce (RCCM)';
      case KycDocumentType.addressProof:
        return 'Justificatif d\'adresse';
    }
  }

  IconData _icon(KycDocumentType type) {
    switch (type) {
      case KycDocumentType.idCard:
        return Icons.badge_outlined;
      case KycDocumentType.selfie:
        return Icons.face_outlined;
      case KycDocumentType.businessRegistration:
        return Icons.store_outlined;
      case KycDocumentType.addressProof:
        return Icons.home_outlined;
    }
  }
}
