import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/locality.dart';
import '../../providers/locality_provider.dart';

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

  Future<void> _useNearMe() async {
    setState(() => _locating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showError('Activez la localisation pour utiliser « Près de moi »');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showError('Autorisez la localisation pour utiliser « Près de moi »');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final nearest = context
          .read<LocalityProvider>()
          .nearestArea(pos.latitude, pos.longitude);
      if (nearest != null) {
        _pick(nearest);
      } else {
        _showError('Commune introuvable');
      }
    } catch (_) {
      _showError('Localisation indisponible');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    final locality = context.watch<LocalityProvider>();
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXXL),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppTheme.spacingS),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(999),
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
    );
  }

  Widget _list(LocalityProvider locality) {
    if (!locality.isLoaded && locality.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppTheme.spacingXL),
        child: Center(child: BrandLoader(size: 32)),
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
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textTertiary),
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
                  child: BrandLoader(size: 20, fast: true),
                )
              : const Icon(
                  Icons.my_location,
                  color: AppColors.textPrimary,
                ),
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
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textTertiary),
            ),
          ),
        ...areas.map((a) {
          final isSelected = widget.selected == a.name;
          return ListTile(
            leading: Icon(
              Icons.location_on_outlined,
              color:
                  isSelected ? AppColors.textPrimary : AppColors.textTertiary,
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
