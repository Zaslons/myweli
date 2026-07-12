import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../models/service.dart';
import '../../../providers/pro_artist_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_service_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_text_field.dart';

const _durationPresets = [15, 30, 45, 60];

class ServiceFormScreen extends StatefulWidget {
  final String? serviceId;

  const ServiceFormScreen({super.key, this.serviceId});

  @override
  State<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends State<ServiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _priceMaxController = TextEditingController();
  final _durationController = TextEditingController();
  final _courtController = TextEditingController();
  final _moyenController = TextEditingController();
  final _longController = TextEditingController();
  // Audit 3.1: which artists can perform this service — empty = toute
  // l'équipe (the engine's unrestricted rule).
  final Set<String> _artistIds = {};
  bool _hasVariants = false;
  bool _prefillDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = context.read<ProAuthProvider>().activeSalonId;
      if (id != null && id.isNotEmpty) {
        context.read<ProArtistProvider>().loadArtists(id);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.serviceId != null && !_prefillDone) {
      final serviceProvider =
          Provider.of<ProServiceProvider>(context, listen: false);
      Service? service;
      for (final s in serviceProvider.services) {
        if (s.id == widget.serviceId) {
          service = s;
          break;
        }
      }
      if (service != null) {
        _nameController.text = service.name;
        _descriptionController.text = service.description;
        _priceController.text = service.price.toStringAsFixed(0);
        _priceMaxController.text = service.priceMax?.toStringAsFixed(0) ?? '';
        _durationController.text = service.durationMinutes.toString();
        final variants = service.durationVariants;
        if (variants.isNotEmpty) {
          _hasVariants = true;
          _courtController.text = variants.court?.toString() ?? '';
          _moyenController.text = variants.moyen?.toString() ?? '';
          _longController.text = variants.long?.toString() ?? '';
        }
        _artistIds.addAll(service.artistIds);
      }
      _prefillDone = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _priceMaxController.dispose();
    _durationController.dispose();
    _courtController.dispose();
    _moyenController.dispose();
    _longController.dispose();
    super.dispose();
  }

  int? _parseVariant(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : int.tryParse(text);
  }

  Widget _variantField(String label, TextEditingController controller) {
    return AppTextField(
      label: label,
      hint: 'min',
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    final serviceProvider =
        Provider.of<ProServiceProvider>(context, listen: false);

    final priceMaxText = _priceMaxController.text.trim();
    final durationVariants = _hasVariants
        ? <String, dynamic>{
            if (_parseVariant(_courtController) != null)
              'court': _parseVariant(_courtController),
            if (_parseVariant(_moyenController) != null)
              'moyen': _parseVariant(_moyenController),
            if (_parseVariant(_longController) != null)
              'long': _parseVariant(_longController),
          }
        : <String, dynamic>{};

    final serviceData = {
      'name': _nameController.text.trim(),
      'description': _descriptionController.text.trim(),
      'price': double.parse(_priceController.text.trim()),
      'priceMax': priceMaxText.isEmpty ? null : double.parse(priceMaxText),
      'durationMinutes': int.parse(_durationController.text.trim()),
      'durationVariants': durationVariants,
      'artistIds': _artistIds.toList(),
      'providerId': authProvider.activeSalonId ?? '',
    };

    final success = widget.serviceId != null
        ? await serviceProvider.updateService(widget.serviceId!, serviceData)
        : await serviceProvider.createService(
            authProvider.activeSalonId ?? authProvider.provider!.id,
            serviceData,
          );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service enregistré'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(serviceProvider.error ?? 'Erreur lors de la sauvegarde'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce service ?'),
        content: const Text(
          'Êtes-vous sûr de vouloir supprimer ce service ? Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final serviceProvider =
        Provider.of<ProServiceProvider>(context, listen: false);
    final success = await serviceProvider.deleteService(widget.serviceId!);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service supprimé'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(serviceProvider.error ?? 'Erreur lors de la suppression'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.serviceId != null
            ? 'Modifier le service'
            : 'Nouveau service'),
      ),
      body: Consumer<ProServiceProvider>(
        builder: (context, serviceProvider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    label: 'Nom du service',
                    hint: 'Ex: Coupe homme',
                    controller: _nameController,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Le nom est requis';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  AppTextField(
                    label: 'Description',
                    hint: 'Décrivez brièvement le service (optionnel)',
                    controller: _descriptionController,
                    maxLines: 3,
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  AppTextField(
                    label: 'Prix — à partir de (XOF)',
                    hint: 'Ex: 5000',
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Le prix est requis';
                      }
                      final cleaned = value.replaceAll(' ', '');
                      if (double.tryParse(cleaned) == null) {
                        return 'Prix invalide';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  AppTextField(
                    label: 'Prix maximum (optionnel)',
                    hint: 'Ex: 25000 — laisser vide si prix fixe',
                    controller: _priceMaxController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final max = double.tryParse(value.trim());
                      if (max == null) return 'Prix invalide';
                      final min = double.tryParse(_priceController.text.trim());
                      if (min != null && max < min) {
                        return 'Doit être ≥ au prix de départ';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  Text(
                    'Durée',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingS),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _durationPresets.map((minutes) {
                      final isSelected =
                          _durationController.text == minutes.toString();
                      return ChoiceChip(
                        label: Text('$minutes min'),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() =>
                                _durationController.text = minutes.toString());
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppTheme.spacingS),
                  AppTextField(
                    label: 'Ou durée personnalisée (minutes)',
                    hint: 'Ex: 90',
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'La durée est requise';
                      }
                      if (int.tryParse(value) == null) {
                        return 'Durée invalide';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppTheme.spacingS),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('La durée varie selon la longueur'),
                    subtitle: const Text(
                      'Définir une durée par longueur de cheveux',
                    ),
                    value: _hasVariants,
                    onChanged: (value) => setState(() => _hasVariants = value),
                  ),
                  if (_hasVariants)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _variantField('Court', _courtController),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _variantField('Moyen', _moyenController),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _variantField('Long', _longController),
                        ),
                      ],
                    ),
                  const SizedBox(height: AppTheme.spacingL),
                  // Audit 3.1: capability assignment — feeds the booking
                  // hub's dimming + the per-artist capacity engine.
                  Consumer<ProArtistProvider>(
                    builder: (context, artistProvider, _) {
                      final artists = artistProvider.artists;
                      if (artists.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'QUI PEUT RÉALISER CE SERVICE ?',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.textTertiary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Aucune sélection = toute l\'équipe.',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          for (final artist in artists)
                            CheckboxListTile(
                              value: _artistIds.contains(artist.id),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _artistIds.add(artist.id);
                                } else {
                                  _artistIds.remove(artist.id);
                                }
                              }),
                              title: Text(artist.name),
                              subtitle: artist.specialization == null
                                  ? null
                                  : Text(artist.specialization!),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            ),
                          const SizedBox(height: AppTheme.spacingL),
                        ],
                      );
                    },
                  ),
                  AppButton(
                    text: 'Enregistrer',
                    onPressed: serviceProvider.isLoading ? null : _handleSave,
                    isLoading: serviceProvider.isLoading,
                  ),
                  if (widget.serviceId != null) ...[
                    const SizedBox(height: AppTheme.spacingM),
                    TextButton(
                      onPressed:
                          serviceProvider.isLoading ? null : _handleDelete,
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.error),
                      child: const Text('Supprimer le service'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
