import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myweli/widgets/common/brand_loader.dart';

import '../../core/constants/communes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

/// Result of the commune picker. `commune == null` means "all communes".
/// The picker returns `null` (not a [CommuneChoice]) when dismissed without a
/// choice, so callers can distinguish "cancelled" from "all communes".
class CommuneChoice {
  final String? commune;
  const CommuneChoice(this.commune);
}

/// Opens the commune picker bottom sheet. Returns the chosen [CommuneChoice],
/// or null if dismissed without choosing.
Future<CommuneChoice?> showCommunePicker(
  BuildContext context, {
  String? selected,
}) {
  return showModalBottomSheet<CommuneChoice?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CommunePickerSheet(selected: selected),
  );
}

class _CommunePickerSheet extends StatefulWidget {
  final String? selected;
  const _CommunePickerSheet({this.selected});

  @override
  State<_CommunePickerSheet> createState() => _CommunePickerSheetState();
}

class _CommunePickerSheetState extends State<_CommunePickerSheet> {
  String _query = '';
  bool _locating = false;

  List<Commune> get _filtered {
    if (_query.isEmpty) return abidjanCommunes;
    final q = _query.toLowerCase();
    return abidjanCommunes
        .where((c) => c.name.toLowerCase().contains(q))
        .toList();
  }

  void _pick(String? commune) {
    Navigator.of(context).pop(CommuneChoice(commune));
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
      final nearest = nearestCommune(pos.latitude, pos.longitude);
      if (!mounted) return;
      if (nearest != null) {
        _pick(nearest.name);
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
            Flexible(
              child: ListView(
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
                  ListTile(
                    leading: const Icon(Icons.public),
                    title: const Text('Toutes les communes'),
                    trailing: widget.selected == null
                        ? const Icon(Icons.check, color: AppColors.textPrimary)
                        : null,
                    onTap: () => _pick(null),
                  ),
                  const Divider(height: 1),
                  ..._filtered.map((c) {
                    final isSelected = widget.selected == c.name;
                    return ListTile(
                      leading: Icon(
                        Icons.location_on_outlined,
                        color: isSelected
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                      ),
                      title: Text(c.name),
                      trailing: isSelected
                          ? const Icon(Icons.check,
                              color: AppColors.textPrimary)
                          : null,
                      selected: isSelected,
                      onTap: () => _pick(c.name),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
