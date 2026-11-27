import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:provider/provider.dart';

import '../../core/location/location_access.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/locality.dart';
import '../../providers/locality_provider.dart';
import 'app_snack_bar.dart';
import 'inline_feedback.dart';

/// Result of the commune picker. `commune == null` means "all communes".
/// The picker returns `null` (not a [CommuneChoice]) when dismissed without a
/// choice, so callers can distinguish "cancelled" from "all communes".
/// Multi-pays MP2: [areaId] carries the locality id — the pro write paths
/// send it so the salon's market facts derive server-side (T57); the
/// consumer filter keeps using the display [commune] name.
class CommuneChoice {
  final String? commune;
  final String? areaId;
  const CommuneChoice(this.commune, {this.areaId});
}

/// Opens the commune picker bottom sheet. Returns the chosen [CommuneChoice],
/// or null if dismissed without choosing. The list renders the LOCALITY TREE
/// (`GET /localities` via [LocalityProvider]) — never a hardcoded list.
/// [allowAll] shows « Toutes les communes » (the consumer filter); pro
/// editors pass false — a salon belongs to exactly one commune.
Future<CommuneChoice?> showCommunePicker(
  BuildContext context, {
  String? selected,
  bool allowAll = true,
}) {
  return showModalBottomSheet<CommuneChoice?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CommunePickerSheet(selected: selected, allowAll: allowAll),
  );
}

class _CommunePickerSheet extends StatefulWidget {
  final String? selected;
  final bool allowAll;
  const _CommunePickerSheet({this.selected, required this.allowAll});

  @override
  State<_CommunePickerSheet> createState() => _CommunePickerSheetState();
}

class _CommunePickerSheetState extends State<_CommunePickerSheet> {
  String _query = '';
  bool _locating = false;

  /// A6: this sheet is a modal, so its failures render inside it — a snackbar
  /// raised here never reaches a screen reader (BlockSemantics) and paints
  /// under the scrim.
  String? _error;

  /// The way out beside [_error], when there is one: « Ouvrir les réglages »
  /// after a refusal for good, or with location off on Android
  /// (consumer-location.md §2.2).
  SnackAction? _errorAction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LocalityProvider>().ensureLoaded();
    });
  }

  List<LocalityArea> _filtered(LocalityProvider locality) {
    final areas = locality.areasOf();
    if (_query.isEmpty) return areas;
    final q = _query.toLowerCase();
    return areas.where((a) => a.name.toLowerCase().contains(q)).toList();
  }

  void _pick(LocalityArea? area) {
    Navigator.of(context).pop(CommuneChoice(area?.name, areaId: area?.id));
  }

  /// « Près de moi »: the shared flow (consumer-location.md §2.2, §5). The
  /// system dialog follows the person's own tap, so it needs no explanation
  /// first; « medium » is enough to find a commune (decision 275), and the
  /// read gives up after [LocationAccess.bound].
  Future<void> _useNearMe() async {
    setState(() {
      _locating = true;
      _error = null;
      _errorAction = null;
    });
    final outcome = await LocationAccess.instance.locate(
      accuracy: LocationAccuracy.medium,
    );
    if (!mounted) return;
    setState(() => _locating = false);
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    switch (outcome) {
      case Located(:final position):
        final nearest = context.read<LocalityProvider>().nearestArea(
          position.latitude,
          position.longitude,
        );
        if (nearest != null) {
          _pick(nearest);
        } else {
          // `nearestArea` has no distance limit: it finds nothing only when
          // the communes are not loaded, or carry no coordinates.
          _showError('Liste des communes indisponible. Réessayez.');
        }
      case LocationRefused():
        _showError(
          'Localisation refusée. Choisissez votre commune dans la liste.',
        );
      case LocationBlocked():
        _showError(
          'Localisation bloquée. Autorisez-la dans les réglages du téléphone, '
          'ou choisissez votre commune dans la liste.',
          action: SnackAction(
            label: 'Ouvrir les réglages',
            onPressed: () =>
                unawaited(LocationAccess.instance.openAppSettings()),
          ),
        );
      case LocationRestricted():
        _showError(
          'La localisation est limitée sur ce téléphone. Choisissez votre '
          'commune dans la liste.',
        );
      case LocationOff() when ios:
        _showError(
          'Le service de localisation est désactivé (Réglages › '
          'Confidentialité et sécurité). Choisissez votre commune dans la '
          'liste.',
        );
      case LocationOff():
        _showError(
          'La localisation du téléphone est désactivée. Activez-la dans les '
          'réglages, ou choisissez votre commune dans la liste.',
          action: SnackAction(
            label: 'Ouvrir les réglages',
            onPressed: () =>
                unawaited(LocationAccess.instance.openLocationSettings()),
          ),
        );
      case LocationFailed():
        _showError(
          'Position introuvable. Réessayez, ou choisissez votre commune dans '
          'la liste.',
        );
    }
  }

  void _showError(String message, {SnackAction? action}) {
    if (!mounted) return;
    // A6: this sheet IS a modal — a snackbar raised here is pruned from the
    // semantics tree and painted under the scrim. The message renders inside.
    setState(() {
      _error = message;
      _errorAction = action;
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    final locality = context.watch<LocalityProvider>();
    // The `Material` is not decoration — it is what makes the tap visible.
    //
    // Flutter 3.44 asserts on this shape (`list_tile.dart`,
    // `_findIntermediateWidget`): a `ListTile` paints its ink on the nearest
    // `Material` ANCESTOR, and the walk up from the tile stops at the first
    // coloured box it meets. This sheet's own background was that box, so every
    // ripple painted BEHIND it. The rows have given no touch feedback for as
    // long as the sheet has existed — the assertion is new, the defect is not.
    //
    // `MaterialType.transparency` paints nothing, so the surface above is
    // untouched and no golden moves; it exists only to give the ink somewhere
    // to land, above the background instead of behind it.
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXXL),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppTheme.spacingS),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingM,
                ),
                child: InlineFeedback(_error, action: _errorAction),
              ),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacingM,
                  AppTheme.spacingM,
                  AppTheme.spacingS,
                  AppTheme.spacingS,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Choisir une commune',
                        style: AppTextStyles.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fermer',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingM,
                ),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Rechercher une commune',
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingS),
              Flexible(child: _list(locality)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(LocalityProvider locality) {
    if (!locality.isLoaded && locality.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppTheme.spacingXL),
        child: Center(child: BrandLoader(size: AppTheme.iconL)),
      );
    }
    if (!locality.isLoaded && locality.error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              locality.error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppTheme.spacingS),
            TextButton(
              onPressed: locality.retry,
              child: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }
    final areas = _filtered(locality);
    return ListView(
      shrinkWrap: true,
      children: [
        ListTile(
          leading: _locating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: BrandLoader(size: AppTheme.iconS, fast: true),
                )
              : const Icon(Icons.my_location, color: AppColors.textPrimary),
          title: const Text('Près de moi'),
          onTap: _locating ? null : _useNearMe,
        ),
        if (widget.allowAll)
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Toutes les communes'),
            trailing: widget.selected == null
                ? const Icon(Icons.check, color: AppColors.textPrimary)
                : null,
            onTap: () => _pick(null),
          ),
        const Divider(height: 1),
        if (areas.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Text(
              'Aucune commune trouvée',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ...areas.map((a) {
          final isSelected = widget.selected == a.name;
          return ListTile(
            leading: Icon(
              Icons.location_on_outlined,
              color: isSelected
                  ? AppColors.textPrimary
                  : AppColors.textTertiary,
            ),
            title: Text(a.name),
            trailing: isSelected
                ? const Icon(Icons.check, color: AppColors.textPrimary)
                : null,
            selected: isSelected,
            onTap: () => _pick(a),
          );
        }),
      ],
    );
  }
}
