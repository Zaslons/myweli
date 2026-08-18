import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/forms/field_errors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/validators.dart';
import '../../providers/admin/admin_client_version_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/form_dialog.dart';
import 'widgets/admin_data_table.dart';
import 'widgets/admin_scaffold.dart';
import 'widgets/status_chip.dart';

/// The client version floors — the lever that retires an old app build.
///
/// Four rows, one per (app × platform), and **no way to add or remove one**:
/// those pairs are a property of what we ship, created by migration 0032, and
/// the backend refuses to create more for the same reason. An admin who could
/// invent `com.myweli.typo` would get a row that governs nothing.
///
/// Design: docs/design/client-version-gate.md §14.
class AdminClientVersionScreen extends StatefulWidget {
  const AdminClientVersionScreen({super.key});

  @override
  State<AdminClientVersionScreen> createState() =>
      _AdminClientVersionScreenState();
}

class _AdminClientVersionScreenState extends State<AdminClientVersionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdminClientVersionProvider>().load(),
    );
  }

  static String _appLabel(Object? id) => switch (id) {
    'com.myweli.app' => 'MyWeli',
    'com.myweli.pro' => 'MyWeli Pro',
    _ => '$id',
  };

  static String _platformLabel(Object? p) =>
      p == 'ios' ? 'iOS' : (p == 'android' ? 'Android' : '$p');

  /// 0 is not "zero", it is "no floor" — and printing `0` would read as a
  /// version number rather than as the absence of one.
  static String _buildLabel(Object? v) => (v is int && v > 0) ? '$v' : 'aucun';

  Future<void> _edit(Map<String, dynamic> floor) async {
    // A GlobalKey so `onSubmit` can reach the fields' state: the dialog frame
    // is the shared component, the fields and their errors belong to the
    // screen. The standard shape for a form inside a dialog.
    final key = GlobalKey<_FloorFieldsState>();
    final saved = await showFormDialog(
      context: context,
      title:
          '${_appLabel(floor['appId'])} · ${_platformLabel(floor['platform'])}',
      submitLabel: 'Enregistrer les seuils',
      child: _FloorFields(key: key, floor: floor),
      // `false` keeps the dialog open with the values still typed — the whole
      // reason this is a FormDialog and not a ConfirmDialog.
      onSubmit: () async => await key.currentState?.submit() ?? false,
    );
    if (saved != true || !mounted) return;
    // Raised only after the dialog is gone: a snackbar under an open dialog is
    // painted behind the barrier and pruned from the semantics tree.
    AppSnackBar.outcome(
      context,
      ok: true,
      success: 'Seuils mis à jour',
      error: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminClientVersionProvider>();
    return AdminScaffold(
      title: 'Versions client',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'En dessous du build minimum, l’application refuse de démarrer et '
              'renvoie vers le magasin. Une plateforme sans lien n’est jamais '
              'bloquée, quel que soit le seuil.',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: AppTheme.spacingM),
            AdminDataTable(
              isLoading: p.isLoading,
              error: p.error,
              onRetry: () => context.read<AdminClientVersionProvider>().load(),
              emptyIcon: Icons.system_update_outlined,
              emptyTitle: 'Aucune version configurée',
              emptyDescription:
                  'Les quatre lignes sont créées par la migration 0032.',
              columns: const [
                AdminColumn('Application', flex: 3),
                AdminColumn('Plateforme', flex: 2),
                AdminColumn('Build minimum', flex: 2),
                AdminColumn('Build recommandé', flex: 2),
                AdminColumn('Lien', flex: 2),
                AdminColumn('', flex: 2),
              ],
              rows: [
                for (final f in p.floors)
                  AdminRow(
                    cells: [
                      Text(_appLabel(f['appId'])),
                      Text(_platformLabel(f['platform'])),
                      Text(_buildLabel(f['minimumBuild'])),
                      Text(_buildLabel(f['recommendedBuild'])),
                      // A status, not the URL. A floor set on a row with no
                      // link is a setting that silently does nothing, and this
                      // column is what makes that visible beforehand.
                      f['updateUrl'] == null
                          ? const StatusChip(
                              label: 'manquant',
                              kind: AdminChipKind.pending,
                            )
                          : const StatusChip(
                              label: 'configuré',
                              kind: AdminChipKind.ok,
                            ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: 120,
                          child: AppButton(
                            text: 'Modifier',
                            type: AppButtonType.secondary,
                            onPressed: () => _edit(f),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The three fields. The dialog frame is the shared [FormDialog]; the fields,
/// their controllers and their error state belong here.
///
/// Not `showReasonDialog`: that takes one sentence-cased text area, and this is
/// two integers and a URL.
class _FloorFields extends StatefulWidget {
  const _FloorFields({super.key, required this.floor});

  final Map<String, dynamic> floor;

  @override
  State<_FloorFields> createState() => _FloorFieldsState();
}

class _FloorFieldsState extends State<_FloorFields> {
  late final _min = TextEditingController(
    text: '${widget.floor['minimumBuild'] ?? 0}',
  );
  late final _rec = TextEditingController(
    text: '${widget.floor['recommendedBuild'] ?? 0}',
  );
  late final _url = TextEditingController(
    text: (widget.floor['updateUrl'] as String?) ?? '',
  );

  final _minFocus = FocusNode();
  final _recFocus = FocusNode();
  final _urlFocus = FocusNode();

  late final _errors = FieldErrors({
    'minimumBuild': Validators.buildNumber('le build minimum'),
    'recommendedBuild': Validators.buildNumber('le build recommandé'),
  });

  late final Map<String, FocusNode> _nodes = {
    'minimumBuild': _minFocus,
    'recommendedBuild': _recFocus,
    'updateUrl': _urlFocus,
  };

  @override
  void dispose() {
    for (final c in [_min, _rec, _url]) {
      c.dispose();
    }
    for (final n in [_minFocus, _recFocus, _urlFocus]) {
      n.dispose();
    }
    super.dispose();
  }

  /// `true` closes the dialog; `false` keeps it open with the values typed.
  Future<bool> submit() async {
    final ok = _errors.validate({
      'minimumBuild': _min.text,
      'recommendedBuild': _rec.text,
    });
    setState(() {});
    if (!ok) {
      focusFirstError(_errors, _nodes);
      return false;
    }

    final p = context.read<AdminClientVersionProvider>();
    final url = _url.text.trim();
    final saved = await p.setFloor(
      appId: widget.floor['appId'] as String,
      platform: widget.floor['platform'] as String,
      minimumBuild: int.parse(_min.text.trim()),
      recommendedBuild: int.parse(_rec.text.trim()),
      updateUrl: url.isEmpty ? null : url,
    );
    if (!mounted) return false;
    if (saved) return true;

    // A server fault that NAMES a field goes to that field, not to a snackbar
    // the operator has to remember while retyping (SYSTEM.md §830 — rule 1
    // applies to server-side faults too).
    final field = switch (p.actionCode) {
      'invalid_minimum_build' => 'minimumBuild',
      'invalid_recommended_build' ||
      'recommended_below_minimum' => 'recommendedBuild',
      'invalid_update_url' => 'updateUrl',
      _ => null,
    };
    setState(() {
      if (field != null) {
        _errors.set(field, p.actionError);
      }
    });
    if (field != null) {
      focusFirstError(_errors, _nodes);
    }
    // Either way the dialog stays open: a field fault is fixed in place, and a
    // non-field fault (an unknown app x platform) is not something a snackbar
    // under a modal barrier could tell them anyway — the message sits on the
    // form.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          label: 'Build minimum',
          hint: '0 = aucun seuil',
          controller: _min,
          focusNode: _minFocus,
          keyboardType: TextInputType.number,
          errorText: _errors['minimumBuild'],
          onChanged: (v) =>
              setState(() => _errors.revalidate('minimumBuild', v)),
        ),
        const SizedBox(height: AppTheme.spacingM),
        AppTextField(
          label: 'Build recommandé',
          hint: '0 = aucune incitation',
          controller: _rec,
          focusNode: _recFocus,
          keyboardType: TextInputType.number,
          errorText: _errors['recommendedBuild'],
          onChanged: (v) =>
              setState(() => _errors.revalidate('recommendedBuild', v)),
        ),
        const SizedBox(height: AppTheme.spacingM),
        AppTextField(
          label: 'Lien de mise à jour (optionnel)',
          hint: 'https://play.google.com/…',
          controller: _url,
          focusNode: _urlFocus,
          errorText: _errors['updateUrl'],
        ),
      ],
    );
  }
}
