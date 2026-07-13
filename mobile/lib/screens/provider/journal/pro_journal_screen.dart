import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/salon_time.dart';
import '../../../models/appointment.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_journal_provider.dart';
import '../../../widgets/common/brand_refresh.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';

/// « Ma journée » — the pro-app day timeline (module `journal` J1b,
/// docs/design/journal-j1b-app.md). Mobile-first equivalent of the web grid:
/// a vertical day with artist filter, week strip, gap slots, and swipe /
/// long-press quick actions. The salon's default appointment view.
class ProJournalScreen extends StatefulWidget {
  const ProJournalScreen({super.key});

  @override
  State<ProJournalScreen> createState() => _ProJournalScreenState();
}

class _ProJournalScreenState extends State<ProJournalScreen> {
  static const _statusFr = {
    AppointmentStatus.pending: 'En attente',
    AppointmentStatus.confirmed: 'Confirmé',
    AppointmentStatus.completed: 'Terminé',
    AppointmentStatus.cancelled: 'Annulé',
    AppointmentStatus.noShow: 'Non présenté',
  };

  String get _providerId => context.read<ProAuthProvider>().activeSalonId ?? '';

  /// Collaborateur own-mode (access R4b §5.3): « Ma journée » shows the
  /// member's own planning only — the lock + hidden actions below; the
  /// server own-filters regardless (T40).
  bool get _ownMode => context.read<ProAuthProvider>().isStaff;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncLock();
      context.read<ProJournalProvider>().load(_providerId);
    });
  }

  /// Keeps the own-mode lock in step with the membership (which can land
  /// asynchronously after a cold start) — re-run from build post-frame.
  void _syncLock() {
    if (!mounted) return;
    final auth = context.read<ProAuthProvider>();
    final journal = context.read<ProJournalProvider>();
    final ownArtist = auth.isStaff ? auth.membership?.artistId : null;
    if (ownArtist != null) {
      journal.lockToArtist(ownArtist);
    } else {
      journal.unlock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final journal = context.watch<ProJournalProvider>();
    final auth = context.watch<ProAuthProvider>();
    final ownMode = auth.isStaff;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLock());
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        // Own-mode grounds the boundary: « {Salon} — votre planning ».
        title: Text(
          ownMode ? '${auth.salonName} — votre planning' : 'Ma journée',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (!ownMode)
            IconButton(
              tooltip: 'Agenda',
              icon: const Icon(Icons.calendar_month),
              onPressed: () => context.push('/pro/appointments'),
            ),
          PopupMenuButton<String>(
            onSelected: (_) =>
                context.read<ProJournalProvider>().toggleCancelled(),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'cancelled',
                checked: journal.showCancelled,
                child: const Text('Voir les annulés'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: ownMode
          ? null // manual booking is a whole-journal act (T40)
          : FloatingActionButton.extended(
              onPressed: () => context.push('/pro/appointment/new'),
              icon: const Icon(Icons.add),
              label: const Text('Nouveau'),
            ),
      body: Column(
        children: [
          _Header(journal: journal, onPick: _pickDate),
          Expanded(child: _body(journal)),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final journal = context.read<ProJournalProvider>();
    final picked = await showDatePicker(
      context: context,
      initialDate: journal.selectedDate,
      firstDate: DateTime.utc(2024),
      lastDate: DateTime.utc(2030),
    );
    if (picked != null) {
      journal.setDate(DateTime.utc(picked.year, picked.month, picked.day));
    }
  }

  Widget _body(ProJournalProvider journal) {
    if (journal.isLoading && journal.day == null) {
      return const LoadingIndicator();
    }
    if (journal.error != null && journal.day == null) {
      return EmptyState(
        icon: Icons.wifi_off,
        title: 'Une erreur est survenue',
        description: journal.error,
        actionText: 'Réessayer',
        onAction: () => journal.load(_providerId),
      );
    }
    final items = journal.visibleAppointments;
    return BrandRefresh(
      onRefresh: journal.refresh,
      child: items.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.event_available,
                  title: 'Aucun rendez-vous ce jour',
                  actionText: _ownMode ? null : '+ Nouveau rendez-vous',
                  onAction: _ownMode
                      ? null
                      : () => context.push('/pro/appointment/new'),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingM,
                AppTheme.spacingS,
                AppTheme.spacingM,
                96,
              ),
              children: _rows(journal, items),
            ),
    );
  }

  /// Interleaves booking cards with tappable « Libre » gap rows (≥30 min).
  List<Widget> _rows(ProJournalProvider journal, List<Appointment> items) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final a = items[i];
      rows.add(_card(journal, a));
      if (i + 1 < items.length) {
        final end = a.appointmentDate.add(
          Duration(minutes: a.durationMinutes ?? 30),
        );
        final nextStart = items[i + 1].appointmentDate;
        if (nextStart.difference(end).inMinutes >= 30) {
          rows.add(_gap(end));
        }
      }
    }
    return rows;
  }

  Widget _gap(DateTime start) {
    // J1b §4.2 (audit 1.11): the « Libre » row carries the ACTIVE artist
    // filter into the prefill ('' = « Sans artiste » and null = « Tous »
    // pass nothing).
    final artistFilter = context.read<ProJournalProvider>().artistFilter;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
      child: InkWell(
        // Own-mode: gaps are informational only (booking = manage.all).
        onTap: _ownMode
            ? null
            : () => context.push(
                  '/pro/appointment/new',
                  extra: {
                    'dateTime': start.toIso8601String(),
                    if (artistFilter != null && artistFilter.isNotEmpty)
                      'artistId': artistFilter,
                  },
                ),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingM,
            vertical: AppTheme.spacingS,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.divider,
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
          child: Row(
            children: [
              const Icon(Icons.add, size: 16, color: AppColors.textTertiary),
              const SizedBox(width: AppTheme.spacingS),
              Text(
                'Libre — ${Formatters.formatTime(start)}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right,
                  size: 16, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(ProJournalProvider journal, Appointment a) {
    final arrived =
        a.status == AppointmentStatus.confirmed && a.arrivedAt != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
      child: Slidable(
        key: ValueKey(a.id),
        // Right swipe → the state-appropriate positive action.
        startActionPane: _startPane(journal, a, arrived),
        endActionPane: _endPane(journal, a),
        child: InkWell(
          onTap: () => context.push('/pro/appointment/${a.id}'),
          onLongPress: () => _actionSheet(journal, a, arrived),
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: _TimelineCard(
            appt: a,
            arrived: arrived,
            statusLabel: arrived ? 'Arrivé' : (_statusFr[a.status] ?? ''),
          ),
        ),
      ),
    );
  }

  ActionPane? _startPane(
    ProJournalProvider journal,
    Appointment a,
    bool arrived,
  ) {
    if (_ownMode) {
      // Collaborateur: « Terminé » on own confirmed bookings only (§5.3).
      if (a.status != AppointmentStatus.confirmed) return null;
      return ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.3,
        children: [
          SlidableAction(
            onPressed: (_) => _run(journal.complete(a.id)),
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            icon: Icons.done_all,
            label: 'Terminé',
          ),
        ],
      );
    }
    if (a.status == AppointmentStatus.pending) {
      return ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.3,
        children: [
          SlidableAction(
            onPressed: (_) => _run(journal.accept(a.id)),
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            icon: Icons.check,
            label: 'Accepter',
          ),
        ],
      );
    }
    if (a.status == AppointmentStatus.confirmed) {
      return ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.3,
        children: [
          SlidableAction(
            onPressed: (_) =>
                _run(arrived ? journal.complete(a.id) : journal.arrive(a.id)),
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            icon: arrived ? Icons.done_all : Icons.login,
            label: arrived ? 'Terminé' : 'Arrivé',
          ),
        ],
      );
    }
    return null;
  }

  ActionPane? _endPane(ProJournalProvider journal, Appointment a) {
    if (_ownMode) return null; // reschedule = manage.all
    if (a.status == AppointmentStatus.cancelled ||
        a.status == AppointmentStatus.completed ||
        a.status == AppointmentStatus.noShow) {
      return null;
    }
    return ActionPane(
      motion: const DrawerMotion(),
      extentRatio: 0.3,
      children: [
        SlidableAction(
          onPressed: (_) => _reschedule(journal, a),
          backgroundColor: AppColors.surfaceVariant,
          foregroundColor: AppColors.textPrimary,
          icon: Icons.schedule,
          label: 'Reprogrammer',
        ),
      ],
    );
  }

  /// Long-press = the full action set (discoverable + a11y — swipes aren't
  /// announced to screen readers).
  Future<void> _actionSheet(
    ProJournalProvider journal,
    Appointment a,
    bool arrived,
  ) async {
    final ownMode = _ownMode;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!ownMode && a.status == AppointmentStatus.pending) ...[
              _sheetAction(Icons.check, 'Accepter', () => journal.accept(a.id)),
              _sheetAction(Icons.close, 'Refuser', () => journal.noShow(a.id),
                  destructive: false),
            ],
            if (a.status == AppointmentStatus.confirmed) ...[
              if (!ownMode && !arrived)
                _sheetAction(
                    Icons.login, 'Client arrivé', () => journal.arrive(a.id)),
              _sheetAction(
                  Icons.done_all, 'Terminé', () => journal.complete(a.id)),
              _sheetAction(
                  Icons.person_off, 'Non présenté', () => journal.noShow(a.id)),
            ],
            if (!ownMode &&
                a.status != AppointmentStatus.cancelled &&
                a.status != AppointmentStatus.completed &&
                a.status != AppointmentStatus.noShow)
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Reprogrammer'),
                onTap: () {
                  Navigator.of(context).pop();
                  _reschedule(journal, a);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _sheetAction(
    IconData icon,
    String label,
    Future<bool> Function() run, {
    bool destructive = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: destructive ? AppColors.error : null),
      title: Text(label),
      onTap: () {
        Navigator.of(context).pop();
        _run(run());
      },
    );
  }

  Future<void> _reschedule(ProJournalProvider journal, Appointment a) async {
    // Picker seeds + result are SALON wall-clock (salon_time.dart) — never
    // the device's zone.
    final date = await showDatePicker(
      context: context,
      initialDate: toSalonTime(a.appointmentDate),
      firstDate: salonToday(),
      lastDate: salonToday().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(toSalonTime(a.appointmentDate)),
    );
    if (time == null || !mounted) return;
    final newDt = salonDateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final ok = await journal.reschedule(a.id, newDt);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(journal.error ?? 'Créneau indisponible.')),
      );
    }
  }

  Future<void> _run(Future<bool> future) async {
    final journal = context.read<ProJournalProvider>();
    final ok = await future;
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(journal.error ?? 'Action impossible.')),
      );
    }
  }
}

// ---- Header (date row + week strip + artist chips) -------------------------

class _Header extends StatelessWidget {
  const _Header({required this.journal, required this.onPick});

  final ProJournalProvider journal;
  final Future<void> Function() onPick;

  @override
  Widget build(BuildContext context) {
    final date = journal.selectedDate;
    final isToday =
        ProJournalProvider.keyOf(date) == ProJournalProvider.keyOf(salonNow());
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => journal.setDate(
                  date.subtract(const Duration(days: 1)),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: onPick,
                  child: Text(
                    isToday
                        ? "Aujourd'hui"
                        : Formatters.formatDate(toSalonTime(date)),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => journal.setDate(
                  date.add(const Duration(days: 1)),
                ),
              ),
            ],
          ),
          _WeekStrip(journal: journal),
          if (journal.day != null && !journal.isLocked)
            _ArtistChips(journal: journal),
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.journal});

  final ProJournalProvider journal;

  static const _labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final selected = journal.selectedDate;
    final monday = selected.subtract(Duration(days: selected.weekday - 1));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingS),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < 7; i++)
            _dayPill(context, monday.add(Duration(days: i)), _labels[i]),
        ],
      ),
    );
  }

  Widget _dayPill(BuildContext context, DateTime d, String label) {
    final key = ProJournalProvider.keyOf(d);
    final isSel = key == ProJournalProvider.keyOf(journal.selectedDate);
    final count = journal.weekCounts[key] ?? 0;
    return GestureDetector(
      onTap: () => journal.setDate(d),
      child: Column(
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSel ? AppColors.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${d.day}',
              style: AppTextStyles.bodyMedium.copyWith(
                color: isSel ? AppColors.secondary : AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: count == 0 ? 0 : (3 + count.clamp(0, 5)).toDouble(),
            height: 4,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtistChips extends StatelessWidget {
  const _ArtistChips({required this.journal});

  final ProJournalProvider journal;

  @override
  Widget build(BuildContext context) {
    final artists = journal.day!.artists;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
        children: [
          _chip(context, 'Tous', journal.artistFilter == null, null),
          for (final a in artists)
            _chip(context, a.name, journal.artistFilter == a.id, a.id),
          if (journal.hasUnassigned)
            _chip(context, 'Sans artiste', journal.artistFilter == '', ''),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, bool selected, String? id) {
    return Padding(
      padding: const EdgeInsets.only(right: AppTheme.spacingS),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => journal.setArtistFilter(selected ? null : id),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.appt,
    required this.arrived,
    required this.statusLabel,
  });

  final Appointment appt;
  final bool arrived;
  final String statusLabel;

  Color get _statusColor {
    if (arrived) return AppColors.success;
    return switch (appt.status) {
      AppointmentStatus.completed => AppColors.textSecondary,
      AppointmentStatus.noShow => AppColors.error,
      AppointmentStatus.cancelled => AppColors.textTertiary,
      AppointmentStatus.pending => AppColors.warning,
      AppointmentStatus.confirmed => AppColors.info,
    };
  }

  @override
  Widget build(BuildContext context) {
    final end = appt.appointmentDate.add(
      Duration(minutes: appt.durationMinutes ?? 30),
    );
    final cancelled = appt.status == AppointmentStatus.cancelled;
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border(left: BorderSide(color: _statusColor, width: 3)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Formatters.formatTime(toSalonTime(appt.appointmentDate)),
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                Formatters.formatTime(toSalonTime(end)),
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
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
                        appt.clientName ?? 'Client',
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                          decoration:
                              cancelled ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if ((appt.clientNoShowCount ?? 0) >= 1) ...[
                      const SizedBox(width: AppTheme.spacingXS),
                      _badge(
                        appt.clientNoShowCount == 1
                            ? '1 absence'
                            : '${appt.clientNoShowCount} absences',
                        (appt.clientNoShowCount ?? 0) >= 2
                            ? AppColors.error
                            : AppColors.textSecondary,
                      ),
                    ],
                    if (appt.depositAmount > 0) ...[
                      const SizedBox(width: AppTheme.spacingXS),
                      const Icon(Icons.savings_outlined,
                          size: 14, color: AppColors.textTertiary),
                    ],
                  ],
                ),
                Text(
                  '${appt.serviceIds.length} prestation(s)',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _badge(statusLabel, _statusColor),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}
