import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/salon_time.dart';
import '../../../models/appointment.dart';
import '../../../models/salon_client.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_clients_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';

/// The client card (module `clients` C1c, docs/design/clients-c1.md §5):
/// identity + call/WhatsApp actions, tags, salon-scoped stats, upcoming
/// booking, team-only notes, visit history, and « Nouveau rendez-vous »
/// prefilled into manual booking.
class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final String clientId;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  String get _providerId {
    final auth = context.read<ProAuthProvider>();
    return auth.activeSalonId ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProClientsProvider>().loadCard(_providerId, widget.clientId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final clients = context.watch<ProClientsProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Fiche client')),
      body: _body(clients),
    );
  }

  Widget _body(ProClientsProvider clients) {
    if (clients.cardLoading) return const LoadingIndicator();
    if (clients.cardNotFound) {
      return const EmptyState(
        icon: Icons.person_off_outlined,
        title: 'Client introuvable',
      );
    }
    if (clients.cardError != null || clients.card == null) {
      return EmptyState(
        icon: Icons.wifi_off,
        title: 'Une erreur est survenue',
        description: clients.cardError,
        actionText: 'Réessayer',
        onAction: () => clients.loadCard(_providerId, widget.clientId),
      );
    }
    final card = clients.card!;
    final client = card.client;
    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      children: [
        _Header(
          client: client,
          onEditTags: () => _openTagSheet(client),
        ),
        const SizedBox(height: AppTheme.spacingM),
        _StatsStrip(stats: card.stats, lastVisitAt: client.lastVisitAt),
        if (card.upcoming != null) ...[
          const SizedBox(height: AppTheme.spacingM),
          _UpcomingCard(upcoming: card.upcoming!),
        ],
        const SizedBox(height: AppTheme.spacingM),
        _NotesSection(
          notes: card.notes,
          onAdd: (body) => clients.addNote(_providerId, widget.clientId, body),
          onDelete: (noteId) =>
              clients.deleteNote(_providerId, widget.clientId, noteId),
        ),
        const SizedBox(height: AppTheme.spacingM),
        _VisitsSection(visits: clients.visits),
        const SizedBox(height: AppTheme.spacingL),
        AppButton(
          text: 'Nouveau rendez-vous',
          onPressed: () => context.push(
            '/pro/appointment/new',
            extra: {
              'clientName': client.displayName,
              'clientPhone': client.phone,
            },
          ),
        ),
        const SizedBox(height: AppTheme.spacingL),
      ],
    );
  }

  Future<void> _openTagSheet(SalonClient client) async {
    final clients = context.read<ProClientsProvider>();
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => _TagSheet(
        initial: client.tags,
        onSave: (tags) =>
            clients.updateTags(_providerId, widget.clientId, tags),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.client, required this.onEditTags});

  final SalonClient client;
  final VoidCallback onEditTags;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.surfaceVariant,
                child: Text(
                  client.displayName.isEmpty
                      ? '?'
                      : client.displayName[0].toUpperCase(),
                  style: AppTextStyles.titleLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            client.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleLarge.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (client.linked) ...[
                          const SizedBox(width: AppTheme.spacingXS),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spacingS,
                              vertical: AppTheme.spacingXS,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusSmall),
                            ),
                            child: Text(
                              'MyWeli',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (client.phone != null)
                      Text(
                        client.phone!,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (client.phone != null) ...[
                IconButton(
                  icon: const Icon(Icons.phone),
                  tooltip: 'Appeler',
                  onPressed: () => launchUrl(Uri.parse('tel:${client.phone}')),
                ),
                IconButton(
                  icon: const Icon(Icons.chat),
                  tooltip: 'WhatsApp',
                  onPressed: () => launchUrl(
                    Uri.parse(
                      'https://wa.me/${client.phone!.replaceAll(RegExp(r'[^0-9]'), '')}',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppTheme.spacingS),
          Wrap(
            spacing: AppTheme.spacingXS,
            runSpacing: AppTheme.spacingXS,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final t in client.tags) Chip(label: Text(t)),
              ActionChip(
                label: Text(
                  client.tags.isEmpty ? '+ Tags' : 'Modifier',
                  style: AppTextStyles.bodySmall,
                ),
                onPressed: onEditTags,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.stats, this.lastVisitAt});

  final SalonClientStats stats;
  final DateTime? lastVisitAt;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, String value, {bool alert = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppTheme.spacingS),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Column(
              children: [
                Text(
                  value,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: alert ? AppColors.error : AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.spacingXS),
                Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );

    final auth = context.read<ProAuthProvider>();
    return Row(
      children: [
        tile('Visites', '${stats.visits}'),
        const SizedBox(width: AppTheme.spacingS),
        tile(
          'Dépensé',
          Formatters.formatCurrency(
            stats.spentFcfa.toDouble(),
            currency: auth.salonCurrency,
          ),
        ),
        const SizedBox(width: AppTheme.spacingS),
        tile('Absences', '${stats.noShows}', alert: stats.noShows >= 2),
        const SizedBox(width: AppTheme.spacingS),
        tile(
          'Dernière',
          lastVisitAt == null
              ? '—'
              : Formatters.formatDate(
                  toSalonTime(lastVisitAt!, tz: auth.salonTimezone)),
        ),
      ],
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.upcoming});

  final Map<String, dynamic> upcoming;

  @override
  Widget build(BuildContext context) {
    final date =
        DateTime.tryParse(upcoming['appointmentDate'] as String? ?? '');
    final id = upcoming['id'] as String?;
    return InkWell(
      onTap: id == null ? null : () => context.push('/pro/appointment/$id'),
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PROCHAIN RENDEZ-VOUS',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: AppTheme.spacingXS),
            Text(
              date == null
                  ? '—'
                  : Formatters.formatDateTime(toSalonTime(
                      date,
                      tz: context.read<ProAuthProvider>().salonTimezone,
                    )),
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesSection extends StatefulWidget {
  const _NotesSection({
    required this.notes,
    required this.onAdd,
    required this.onDelete,
  });

  final List<SalonClientNote> notes;
  final Future<bool> Function(String body) onAdd;
  final Future<bool> Function(String noteId) onDelete;

  @override
  State<_NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends State<_NotesSection> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() => _busy = true);
    final ok = await widget.onAdd(_controller.text.trim());
    if (mounted) {
      setState(() => _busy = false);
      if (ok) _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notes',
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            'Visible uniquement par votre équipe.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          AppTextField(
            controller: _controller,
            hint: 'Ajouter une note…',
            maxLength: 500,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              text: 'Ajouter',
              isFullWidth: false,
              isLoading: _busy,
              onPressed:
                  (_busy || _controller.text.trim().isEmpty) ? null : _add,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          if (widget.notes.isEmpty)
            Text(
              'Aucune note pour l’instant.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            for (final n in widget.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTheme.spacingS),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.body,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingXS),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${n.authorName} · '
                            '${Formatters.formatRelative(n.createdAt)}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => widget.onDelete(n.id),
                            child: Text(
                              'Supprimer',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textTertiary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _VisitsSection extends StatelessWidget {
  const _VisitsSection({required this.visits});

  final List<Appointment> visits;

  static const _statusFr = {
    AppointmentStatus.pending: 'En attente',
    AppointmentStatus.confirmed: 'Confirmé',
    AppointmentStatus.completed: 'Terminé',
    AppointmentStatus.cancelled: 'Annulé',
    AppointmentStatus.noShow: 'Non présenté',
  };

  Color _statusColor(AppointmentStatus s) => switch (s) {
        AppointmentStatus.completed => AppColors.success,
        AppointmentStatus.noShow => AppColors.error,
        AppointmentStatus.cancelled => AppColors.textTertiary,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Historique des visites',
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          if (visits.isEmpty)
            Text(
              'Aucune visite enregistrée.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            for (final v in visits)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppTheme.spacingXS,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        Formatters.formatDateTime(toSalonTime(
                          v.appointmentDate,
                          tz: context.read<ProAuthProvider>().salonTimezone,
                        )),
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      Formatters.formatCurrency(
                        v.totalPrice,
                        currency: context.read<ProAuthProvider>().salonCurrency,
                      ),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingS),
                    Text(
                      _statusFr[v.status] ?? v.status.name,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: _statusColor(v.status),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _TagSheet extends StatefulWidget {
  const _TagSheet({required this.initial, required this.onSave});

  final List<String> initial;
  final Future<bool> Function(List<String> tags) onSave;

  @override
  State<_TagSheet> createState() => _TagSheetState();
}

class _TagSheetState extends State<_TagSheet> {
  late final List<String> _tags = List.of(widget.initial);
  final _customController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _toggle(String tag) {
    setState(() {
      if (_tags.contains(tag)) {
        _tags.remove(tag);
      } else if (_tags.length < 10) {
        _tags.add(tag);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await widget.onSave(_tags);
    if (mounted) {
      setState(() => _busy = false);
      if (ok) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = {
      ...salonClientPresetTags,
      ...widget.initial,
      ..._tags,
    }.toList();
    return Padding(
      padding: EdgeInsets.only(
        left: AppTheme.spacingL,
        right: AppTheme.spacingL,
        top: AppTheme.spacingL,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spacingL,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tags',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          Wrap(
            spacing: AppTheme.spacingXS,
            runSpacing: AppTheme.spacingXS,
            children: [
              for (final t in choices)
                FilterChip(
                  label: Text(t),
                  selected: _tags.contains(t),
                  onSelected: (_) => _toggle(t),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingM),
          AppTextField(
            controller: _customController,
            label: 'Tag personnalisé',
            hint: 'Ex : Mariée juin',
            maxLength: 24,
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                final t = _customController.text.trim();
                if (t.isNotEmpty && !_tags.contains(t) && _tags.length < 10) {
                  setState(() {
                    _tags.add(t);
                    _customController.clear();
                  });
                }
              },
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          AppButton(
            text: 'Enregistrer',
            isLoading: _busy,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}
