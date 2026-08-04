import 'package:flutter/material.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/booking_horizons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/blocked_dates.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/salon_time.dart';
import '../../../models/availability.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_availability_provider.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/confirm_dialog.dart';
import '../../../widgets/common/myweli_date_picker.dart';
import '../../../widgets/common/myweli_month_grid.dart' show CalendarDay;
import '../../../widgets/common/myweli_time_picker.dart';
import '../../../widgets/provider/weekly_hours_editor.dart';

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  String _resolvedProviderId(BuildContext context) {
    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    return authProvider.activeSalonId ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.provider != null) {
        final availabilityProvider = Provider.of<ProAvailabilityProvider>(
          context,
          listen: false,
        );
        availabilityProvider.loadAvailability(_resolvedProviderId(context));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Disponibilité')),
      body: Consumer2<ProAuthProvider, ProAvailabilityProvider>(
        builder: (context, authProvider, availabilityProvider, _) {
          if (!authProvider.isAuthenticated) {
            return const Center(child: Text('Veuillez vous connecter'));
          }

          if (availabilityProvider.isLoading &&
              availabilityProvider.availability == null) {
            return const Center(child: LoadingIndicator());
          }

          final availability = availabilityProvider.availability;
          if (availability == null) {
            return Center(
              child: Text(
                availabilityProvider.error ?? 'Aucune disponibilité configurée',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            );
          }

          return BrandRefresh(
            onRefresh: () async {
              if (authProvider.provider != null) {
                await availabilityProvider.loadAvailability(
                  _resolvedProviderId(context),
                );
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppTheme.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BookingWindowSection(
                    bookingHorizonDays: availability.bookingHorizonDays,
                    minimumNoticeMinutes: availability.minimumNoticeMinutes,
                    onHorizonChanged: (days) => _setWindow(
                      context,
                      availability,
                      availabilityProvider,
                      _resolvedProviderId(context),
                      horizonDays: days,
                    ),
                    onNoticeChanged: (minutes) => _setWindow(
                      context,
                      availability,
                      availabilityProvider,
                      _resolvedProviderId(context),
                      noticeMinutes: minutes,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  _BufferSection(
                    bufferMinutes: availability.bufferMinutes,
                    onChanged: (minutes) => _setBuffer(
                      context,
                      minutes,
                      availability,
                      availabilityProvider,
                      _resolvedProviderId(context),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  Text(
                    'Pauses',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingXS),
                  Text(
                    'Une pause récurrente par jour (ex. déjeuner). '
                    'Aucun créneau ne sera proposé pendant ces heures.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingS),
                  WeeklyHoursEditor(
                    hours: availability.breaks,
                    offLabel: 'Aucune',
                    defaultStart: const TimeOfDay(hour: 12, minute: 0),
                    defaultEnd: const TimeOfDay(hour: 13, minute: 0),
                    onChanged: (breaks) => _setBreaks(
                      context,
                      breaks,
                      availability,
                      availabilityProvider,
                      _resolvedProviderId(context),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  Text(
                    'Horaires de travail',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  ...List.generate(7, (index) {
                    final dayName = _getDayName(index);
                    final daySlots = availability.weeklySchedule[index] ?? [];
                    return _DayScheduleCard(
                      dayIndex: index,
                      dayName: dayName,
                      timeSlots: daySlots,
                      onEdit: () => _showEditDayDialog(
                        context,
                        index,
                        dayName,
                        daySlots,
                        availabilityProvider,
                        _resolvedProviderId(context),
                      ),
                    );
                  }),
                  const SizedBox(height: AppTheme.spacingL),
                  Text(
                    'Dates bloquées',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingSM),
                  if (availability.blockedDates.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(AppTheme.spacingM),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusLarge,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: AppTheme.spacingSM),
                          Expanded(
                            child: Text(
                              'Aucune date bloquée',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...availability.blockedDates.map(
                      (date) => _BlockedDateCard(
                        date: date,
                        tz: context.read<ProAuthProvider>().salonTimezone,
                        onRemove: () => _removeBlockedDate(
                          context,
                          date,
                          availability,
                          availabilityProvider,
                          _resolvedProviderId(context),
                        ),
                      ),
                    ),
                  const SizedBox(height: AppTheme.spacingSM),
                  OutlinedButton.icon(
                    onPressed: () => _showBlockedDatesPicker(
                      context,
                      availability,
                      availabilityProvider,
                      _resolvedProviderId(context),
                    ),
                    icon: const Icon(Icons.edit_calendar),
                    label: const Text('Gérer les dates bloquées'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _getDayName(int dayIndex) {
    const days = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche',
    ];
    return days[dayIndex];
  }

  void _showEditDayDialog(
    BuildContext context,
    int dayIndex,
    String dayName,
    List<TimeSlot> currentSlots,
    ProAvailabilityProvider provider,
    String providerId,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => _DayScheduleEditScreen(
          dayIndex: dayIndex,
          dayName: dayName,
          initialSlots: currentSlots,
          provider: provider,
          providerId: providerId,
        ),
      ),
    );
  }

  /// A14e — block or unblock several days in one gesture.
  ///
  /// **Replaces a one-day-per-write flow.** « Bloquer les fêtes » cost fourteen
  /// full round trips, each one a DELETE-and-reinsert of the salon's entire
  /// availability, and « tous les dimanches d'août » cost five — which a date
  /// RANGE could not express at all. A toggle is the only single mode that
  /// expresses both real jobs, and the only one that maps onto the model that
  /// exists: `blockedDates` is a list of days, not a rule.
  ///
  /// The picker returns a **delta**, and the reason is a silent data loss — see
  /// `applyBlockedDaysDelta`.
  void _showBlockedDatesPicker(
    BuildContext context,
    Availability availability,
    ProAvailabilityProvider provider,
    String providerId,
  ) async {
    // A blocked date is the ACTIVE SALON's calendar day (salon_time.dart).
    final tz = context.read<ProAuthProvider>().salonTimezone;
    final today = salonToday(tz: tz);
    final firstDay = CalendarDay.of(today);

    // Seeded ONLY with days inside the picker's own range. A day before
    // `firstDate` would render selected and inert — `primary` fill under
    // `textTertiary` ink, with a dead tap — and the picker asserts against it.
    // The past ones are not lost: they keep their card and its delete button.
    final seeded = {
      for (final d in availability.blockedDates)
        if (!CalendarDay.of(toSalonTime(d, tz: tz)).isBefore(firstDay))
          CalendarDay.of(toSalonTime(d, tz: tz)),
    };

    final delta = await showMyweliMultiDatePicker(
      context: context,
      initialSelection: seeded,
      firstDate: today,
      // Deliberately NOT the salon's own `bookingHorizonDays`: blocking is
      // PLANNING, not booking. A salon may mark Christmas while its window is
      // 30 days and widen the window later, and the write is harmless either
      // way. Recorded so a future sweep does not "fix" it into agreement.
      lastDate: today.add(kBookingHorizon),
      today: today,
      // **« Dates à bloquer » is the string §21 row 79 was opened with, and
      // it took two passes to actually fix.** Making « Réinitialiser » an
      // icon took it from « Dat… » to « Dates à bloqu… » — better, still cut.
      // This bar draws a close leading AND that reset action the moment the
      // pro touches a day, so its budget is 232dp, not the 280 an action-less
      // bar gets. « Jours bloqués » also stops naming only one direction, on a
      // screen A14e made deliberately bidirectional.
      helpText: 'Jours bloqués',
    );
    if (delta == null || !context.mounted) return;
    if (delta.added.isEmpty && delta.removed.isEmpty) return;

    if (!await _confirmBlockedDatesChange(context, delta, tz)) return;
    if (!context.mounted) return;

    await provider.updateAvailability(
      providerId,
      availability.copyWith(
        blockedDates: applyBlockedDaysDelta(
          current: availability.blockedDates,
          added: delta.added,
          removed: delta.removed,
          tz: tz,
        ),
      ),
    );
    if (!context.mounted) return;
    if (provider.error != null) {
      AppSnackBar.show(context, provider.error!, kind: SnackKind.error);
      return;
    }
    // Feedback is owed when the change is not visible on the surface that
    // caused it: a chip shows its own new state, a popped modal does not.
    AppSnackBar.show(context, _changeSummary(delta), kind: SnackKind.success);
  }

  String _changeSummary(DaySelectionDelta delta) {
    final parts = [
      if (delta.added.isNotEmpty)
        Formatters.count(delta.added.length, 'date bloquée', 'dates bloquées'),
      if (delta.removed.isNotEmpty)
        Formatters.count(
          delta.removed.length,
          'date débloquée',
          'dates débloquées',
        ),
    ];
    return parts.join(' · ');
  }

  /// **One rule: every write to `blockedDates` passes exactly one confirm, the
  /// verb names the direction, and the rung is set by the worst half present.**
  ///
  /// A14a's comment on the old dialog justified it by the picker popping on the
  /// first tap — Material's OK was doing double duty as the commit gesture for
  /// a server write. The multi-picker has its own explicit, labelled button, so
  /// that justification is satisfied by the screen. It does not carry, for one
  /// reason: the gesture can now **unblock**, and unblocking is the direction
  /// that produces an unwanted booking. Removal had NO confirmation at all —
  /// the more dangerous half was the unguarded one.
  Future<bool> _confirmBlockedDatesChange(
    BuildContext context,
    DaySelectionDelta delta,
    String? tz,
  ) {
    final adds = delta.added.length;
    final removes = delta.removed.length;

    if (removes == 0) {
      // n = 1 names the date; n > 1 gives a count. Enumerating three dates
      // would be a third place the same information lives, and the grid and
      // the summary bar are both better at it — but losing the named date in
      // the commonest case would be a copy regression, so the singular branch
      // keeps A14a's exact sentence.
      return showConfirmDialog(
        context,
        title: adds == 1 ? 'Bloquer cette date ?' : 'Bloquer ces dates ?',
        message: adds == 1
            ? 'Le ${Formatters.formatDate(delta.added.first.toDateTime())}, '
                  'votre salon n’acceptera aucune réservation.'
            : 'Votre salon n’acceptera aucune réservation pendant ces '
                  '${Formatters.count(adds, 'journée', 'journées')}.',
        confirmLabel: adds == 1
            ? 'Bloquer'
            : 'Bloquer ${Formatters.count(adds, 'date', 'dates')}',
        icon: Icons.block,
      );
    }

    if (adds == 0) {
      return showConfirmDialog(
        context,
        title: removes == 1
            ? 'Débloquer cette date ?'
            : 'Débloquer ces dates ?',
        message: removes == 1
            ? 'Le ${Formatters.formatDate(delta.removed.first.toDateTime())}, '
                  'votre salon acceptera de nouveau des réservations.'
            : 'Votre salon acceptera de nouveau des réservations pendant ces '
                  '${Formatters.count(removes, 'journée', 'journées')}.',
        confirmLabel: removes == 1
            ? 'Débloquer'
            : 'Débloquer ${Formatters.count(removes, 'date', 'dates')}',
        icon: Icons.event_available,
        // Opening your calendar is not destructive, and `ConfirmDialog`'s own
        // docstring warns that red on a non-destructive action dilutes the
        // signal.
        isDestructive: false,
      );
    }

    // Mixed. No single verb names both directions, so the confirm names the
    // OUTCOME — which §15 permits, and which « Bloquer » or « Débloquer »
    // would misname for half the change. Two icon-led lines rather than one
    // paragraph, so the direction is not carried by a word buried mid-sentence.
    return showConfirmDialog(
      context,
      title: 'Modifier vos dates bloquées ?',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DeltaLine(
            icon: Icons.block,
            text: Formatters.count(
              adds,
              'date sera bloquée',
              'dates seront bloquées',
            ),
          ),
          const SizedBox(height: AppTheme.spacingXS),
          _DeltaLine(
            icon: Icons.event_available,
            text: Formatters.count(
              removes,
              'date sera débloquée',
              'dates seront débloquées',
            ),
          ),
        ],
      ),
      confirmLabel: 'Enregistrer',
      icon: Icons.edit_calendar,
    );
  }

  Future<void> _setWindow(
    BuildContext context,
    Availability availability,
    ProAvailabilityProvider provider,
    String providerId, {
    int? horizonDays,
    int? noticeMinutes,
  }) async {
    // Exactly one of the two arrives per tap; « nothing changed » means the
    // supplied one already holds that value. Spelled out rather than folded
    // into one `||`, which reads as an accident on two optional parameters.
    final horizonUnchanged =
        horizonDays == null || horizonDays == availability.bookingHorizonDays;
    final noticeUnchanged =
        noticeMinutes == null ||
        noticeMinutes == availability.minimumNoticeMinutes;
    if (horizonUnchanged && noticeUnchanged) return;
    await provider.updateAvailability(
      providerId,
      availability.copyWith(
        bookingHorizonDays: horizonDays,
        minimumNoticeMinutes: noticeMinutes,
      ),
    );
    if (context.mounted && provider.error != null) {
      AppSnackBar.show(context, provider.error!, kind: SnackKind.error);
    }
  }

  Future<void> _setBuffer(
    BuildContext context,
    int minutes,
    Availability availability,
    ProAvailabilityProvider provider,
    String providerId,
  ) async {
    if (minutes == availability.bufferMinutes) return;
    await provider.updateAvailability(
      providerId,
      availability.copyWith(bufferMinutes: minutes),
    );
    if (context.mounted && provider.error != null) {
      AppSnackBar.show(context, provider.error!, kind: SnackKind.error);
    }
  }

  Future<void> _setBreaks(
    BuildContext context,
    Map<int, List<TimeSlot>> breaks,
    Availability availability,
    ProAvailabilityProvider provider,
    String providerId,
  ) async {
    await provider.updateAvailability(
      providerId,
      availability.copyWith(breaks: breaks),
    );
    if (context.mounted && provider.error != null) {
      AppSnackBar.show(context, provider.error!, kind: SnackKind.error);
    }
  }

  /// The per-card delete — the only way to reach a PAST blocked date, since
  /// the picker's range starts today.
  ///
  /// **It now confirms.** Adding always did and removing never did, which put
  /// the guard on the safer half: unblocking is the direction that produces an
  /// unwanted booking. One rule across the screen (see
  /// `_confirmBlockedDatesChange`), and `isDestructive: false` because opening
  /// your calendar destroys nothing.
  void _removeBlockedDate(
    BuildContext context,
    DateTime date,
    Availability availability,
    ProAvailabilityProvider provider,
    String providerId,
  ) async {
    final tz = context.read<ProAuthProvider>().salonTimezone;
    final day = CalendarDay.of(toSalonTime(date, tz: tz));

    final confirmed = await showConfirmDialog(
      context,
      title: 'Débloquer cette date ?',
      message:
          'Le ${Formatters.formatDate(toSalonTime(date, tz: tz))}, votre '
          'salon acceptera de nouveau des réservations.',
      confirmLabel: 'Débloquer',
      icon: Icons.event_available,
      isDestructive: false,
    );
    if (!confirmed || !context.mounted) return;

    await provider.updateAvailability(
      providerId,
      availability.copyWith(
        // The same composer the picker uses, so « remove one » and « remove
        // three » cannot drift apart — and so this path also matches on the
        // SALON day rather than the stored instant's raw fields.
        blockedDates: applyBlockedDaysDelta(
          current: availability.blockedDates,
          added: const {},
          removed: {day},
          tz: tz,
        ),
      ),
    );
    if (context.mounted && provider.error != null) {
      AppSnackBar.show(context, provider.error!, kind: SnackKind.error);
    }
  }
}

/// The bookable window — how far ahead, and how soon, clients may book (A14d).
///
/// Deliberately the same shape as [_BufferSection] below: one card, an icon and
/// a `Flexible` title, a sentence, and a `Wrap` of `ChoiceChip`s that save on
/// tap. Two settings live here rather than two cards because they are one
/// concept — the ends of a single window — and a salon reasons about them
/// together.
///
/// **The presets cannot express an invalid pair.** The server refuses a notice
/// reaching past the horizon (`isBookableWindow`), and the widest notice here
/// (24 h) is inside the shortest horizon (1 month) by construction. Pinned by a
/// test, so editing this list cannot silently offer a combination the API
/// rejects.
class _BookingWindowSection extends StatelessWidget {
  final int bookingHorizonDays;
  final int minimumNoticeMinutes;
  final ValueChanged<int> onHorizonChanged;
  final ValueChanged<int> onNoticeChanged;

  const _BookingWindowSection({
    required this.bookingHorizonDays,
    required this.minimumNoticeMinutes,
    required this.onHorizonChanged,
    required this.onNoticeChanged,
  });

  static String horizonLabel(int days) => switch (days) {
    30 => '1 mois',
    90 => '3 mois',
    180 => '6 mois',
    365 => '1 an',
    _ => '$days jours',
  };

  static String noticeLabel(int minutes) => switch (minutes) {
    0 => 'Aucun',
    60 => '1 h',
    720 => '12 h',
    1440 => '24 h',
    _ => '$minutes min',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `Flexible`, not a fixed row: an icon does not text-scale, so at
          // 200% the title grows and the glyph does not (§21 row 68).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.event_available,
                size: AppTheme.iconS,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppTheme.spacingS),
              Flexible(
                child: Text(
                  'Fenêtre de réservation',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            'Jusqu’où vos clients peuvent réserver à l’avance, et le délai '
            'minimum avant un rendez-vous. Vos propres réservations ne sont '
            'pas concernées.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            'Réservations jusqu’à',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingXS),
          Wrap(
            spacing: AppTheme.spacingS,
            runSpacing: AppTheme.spacingS,
            children: BookingWindowPresets.horizons.map((days) {
              return ChoiceChip(
                label: Text(horizonLabel(days)),
                selected: bookingHorizonDays == days,
                onSelected: (_) => onHorizonChanged(days),
              );
            }).toList(),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            'Délai minimum',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingXS),
          Wrap(
            spacing: AppTheme.spacingS,
            runSpacing: AppTheme.spacingS,
            children: BookingWindowPresets.notices.map((minutes) {
              return ChoiceChip(
                label: Text(noticeLabel(minutes)),
                selected: minimumNoticeMinutes == minutes,
                onSelected: (_) => onNoticeChanged(minutes),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _BufferSection extends StatelessWidget {
  final int bufferMinutes;
  final ValueChanged<int> onChanged;

  static const _presets = [0, 10, 15, 30];

  const _BufferSection({required this.bufferMinutes, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A12 — §21 row 68's finding #10, and the same mechanism as the pro
          // dashboard's `_StatCard`: **an icon does not text-scale.** The
          // theme sets no `applyTextScaling`, so the glyph stays 20dp while
          // « Temps de battement » goes from ~144 to ~288 in a 296dp card —
          // ~20dp over at 200%.
          //
          // `Flexible` rather than a `Wrap` here: unlike the stat card's
          // « Aujourd'hui », this title is three words and CAN wrap its way
          // out, so it takes the space it needs and the icon stays beside it.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.hourglass_bottom,
                size: AppTheme.iconS,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppTheme.spacingS),
              Flexible(
                child: Text(
                  'Temps de battement',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            'Pause automatique entre deux rendez-vous (nettoyage, '
            'préparation). Les créneaux proposés aux clients en tiennent compte.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Wrap(
            spacing: AppTheme.spacingS,
            runSpacing: AppTheme.spacingS,
            children: _presets.map((minutes) {
              return ChoiceChip(
                label: Text(minutes == 0 ? 'Aucun' : '$minutes min'),
                selected: bufferMinutes == minutes,
                onSelected: (_) => onChanged(minutes),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _DayScheduleCard extends StatelessWidget {
  final int dayIndex;
  final String dayName;
  final List<TimeSlot> timeSlots;
  final VoidCallback onEdit;

  const _DayScheduleCard({
    required this.dayIndex,
    required this.dayName,
    required this.timeSlots,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingS),
      child: ListTile(
        title: Text(
          dayName,
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: timeSlots.isEmpty
            ? Text(
                'Fermé',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              )
            : Wrap(
                spacing: AppTheme.spacingS,
                runSpacing: AppTheme.spacingXS,
                children: timeSlots.map((slot) {
                  final start = Formatters.formatTime(slot.startTime);
                  final end = Formatters.formatTime(slot.endTime);
                  return Chip(
                    label: Text('$start - $end'),
                    backgroundColor: slot.isAvailable
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.error.withValues(alpha: 0.1),
                  );
                }).toList(),
              ),
        trailing: IconButton(
          tooltip: 'Modifier',
          icon: const Icon(Icons.edit),
          onPressed: onEdit,
        ),
      ),
    );
  }
}

class _BlockedDateCard extends StatelessWidget {
  final DateTime date;
  final String? tz;
  final VoidCallback onRemove;

  const _BlockedDateCard({
    required this.date,
    required this.tz,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingS),
      child: ListTile(
        leading: const Icon(Icons.block, color: AppColors.error),
        title: Text(
          // The SALON's day, not the raw instant's. A blocked date is stored
          // as salon midnight in UTC, so on any salon east or west of
          // Greenwich `formatDate` on the raw value names the wrong day — the
          // client-side mirror of the `blocked_date` bug fixed in the same PR.
          // Every other reader already converts: mock_appointment_service and
          // mock_provider_service both compare through `toSalonTime`.
          Formatters.formatDate(toSalonTime(date, tz: tz)),
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        trailing: IconButton(
          tooltip: 'Supprimer',
          icon: const Icon(Icons.delete, color: AppColors.error),
          onPressed: onRemove,
        ),
      ),
    );
  }
}

class _DayScheduleEditScreen extends StatefulWidget {
  final int dayIndex;
  final String dayName;
  final List<TimeSlot> initialSlots;
  final ProAvailabilityProvider provider;
  final String providerId;

  const _DayScheduleEditScreen({
    required this.dayIndex,
    required this.dayName,
    required this.initialSlots,
    required this.provider,
    required this.providerId,
  });

  @override
  State<_DayScheduleEditScreen> createState() => _DayScheduleEditScreenState();
}

class _DayScheduleEditScreenState extends State<_DayScheduleEditScreen> {
  late List<TimeSlot> _slots;

  @override
  void initState() {
    super.initState();
    _slots = List.from(widget.initialSlots);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        // The bare day name. « Horaires - {jour} » interpolated a datum into a
        // bar that has no width to promise it (§13.3 / A15) — and on a bar that
        // also carries an « Ajouter un créneau » action. It spent five glyphs
        // and an ASCII hyphen (§17.1 would want « — », which is *wider*, so
        // that repair alone would have made it worse) saying what the screen
        // the user just tapped through already said.
        title: Text(widget.dayName),
        actions: [
          IconButton(
            tooltip: 'Ajouter un créneau',
            icon: const Icon(Icons.add),
            onPressed: _addTimeSlot,
          ),
        ],
      ),
      body: Consumer<ProAvailabilityProvider>(
        builder: (context, provider, _) {
          final availability = provider.availability;
          if (availability == null) {
            return const Center(child: Text('Chargement…'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_slots.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacingL),
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: AppTheme.iconXL,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: AppTheme.spacingSM),
                        Text(
                          'Aucun créneau horaire',
                          style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacingS),
                        Text(
                          'Ajoutez des créneaux pour définir vos horaires',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textTertiary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  ...List.generate(_slots.length, (index) {
                    return _TimeSlotCard(
                      slot: _slots[index],
                      onEdit: () => _editTimeSlot(index),
                      onRemove: () => _removeTimeSlot(index),
                    );
                  }),
                const SizedBox(height: AppTheme.spacingL),
                ElevatedButton(
                  onPressed: provider.isLoading
                      ? null
                      : () => _saveSchedule(availability, provider),
                  child: provider.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: BrandLoader(size: AppTheme.iconS, fast: true),
                        )
                      : const Text('Enregistrer'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _addTimeSlot() {
    _showTimeSlotDialog(null);
  }

  void _editTimeSlot(int index) {
    _showTimeSlotDialog(index);
  }

  void _showTimeSlotDialog(int? index) async {
    TimeOfDay? startTime;
    TimeOfDay? endTime;

    if (index != null) {
      final slot = _slots[index];
      startTime = TimeOfDay.fromDateTime(slot.startTime);
      endTime = TimeOfDay.fromDateTime(slot.endTime);
    }

    // **One screen, not two identical modals** (A14b). This was two
    // `showTimePicker`s with **no `helpText` on either**, so they were visually
    // identical with nothing on screen saying which one you were in — and the
    // second one's seed had to be derived arithmetically
    // (`pickedStart.hour + 1`) precisely because the two dialogs could not see
    // each other. The range picker shows both halves at once and drags the end
    // forward itself.
    final picked = await showMyweliTimeRangePicker(
      context: context,
      initialStart: startTime ?? const TimeOfDay(hour: 9, minute: 0),
      initialEnd:
          endTime ??
          TimeOfDay(
            hour: startTime?.hour ?? 10,
            minute: startTime?.minute ?? 0,
          ),
      // 232dp, not 280: this bar has a close leading and a save action. The
      // noun is what the screen the pro just tapped through already says.
      helpText: index == null ? 'Nouveau' : 'Modifier',
    );

    if (picked == null || !mounted) return;
    final pickedStart = picked.start;
    final pickedEnd = picked.end;

    // §18 — a wall-clock the user picked IS salon time, so it becomes a UTC
    // instant through `salonDateTime`, exactly as the blocked-date picker at
    // `:261` already did. This built `DateTime(y, m, d, h, m)` — device-local,
    // the shape §18 forbids outright — and A10's own sweep walked past it,
    // converting the `now` on the line above and leaving the two constructions
    // that consume it. The pin cannot see this: there is no clock token here.
    final tz = context.read<ProAuthProvider>().salonTimezone;
    final today = salonToday(tz: tz);
    final startDateTime = salonDateTime(
      today.year,
      today.month,
      today.day,
      hour: pickedStart.hour,
      minute: pickedStart.minute,
      tz: tz,
    );
    final endDateTime = salonDateTime(
      today.year,
      today.month,
      today.day,
      hour: pickedEnd.hour,
      minute: pickedEnd.minute,
      tz: tz,
    );

    // **The « L'heure de fin doit être après l'heure de début » snackbar used to
    // be here, and A14b deleted it rather than restyling it.** It existed only
    // because dialog 2 could not be given a lower bound of `pickedStart`, and it
    // cost the user both answers to say so. `MyweliTimeRangePicker` will not
    // offer an end at or before the start, so the state this caught is now
    // unreachable — which is the difference between a validation and a
    // constraint. `myweli_time_picker_test.dart` asserts the guarantee this
    // deletion now relies on.

    final newSlot = TimeSlot(
      startTime: startDateTime,
      endTime: endDateTime,
      isAvailable: true,
    );

    setState(() {
      if (index != null) {
        _slots[index] = newSlot;
      } else {
        _slots.add(newSlot);
      }
      // Sort slots by start time
      _slots.sort((a, b) => a.startTime.compareTo(b.startTime));
    });
  }

  void _removeTimeSlot(int index) {
    setState(() {
      _slots.removeAt(index);
    });
  }

  Future<void> _saveSchedule(
    Availability availability,
    ProAvailabilityProvider provider,
  ) async {
    final updatedSchedule = Map<int, List<TimeSlot>>.from(
      availability.weeklySchedule,
    );
    updatedSchedule[widget.dayIndex] = _slots;

    final updatedAvailability = availability.copyWith(
      weeklySchedule: updatedSchedule,
    );

    final success = await provider.updateAvailability(
      widget.providerId,
      updatedAvailability,
    );
    if (mounted) {
      if (success) {
        AppSnackBar.show(
          context,
          'Horaires enregistrés',
          kind: SnackKind.success,
        );
        Navigator.pop(context);
      } else {
        AppSnackBar.show(
          context,
          provider.error ?? 'Erreur lors de l’enregistrement',
          kind: SnackKind.error,
        );
      }
    }
  }
}

class _TimeSlotCard extends StatelessWidget {
  final TimeSlot slot;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _TimeSlotCard({
    required this.slot,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingS),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: slot.isAvailable
              ? AppColors.primary.withValues(alpha: 0.2)
              : AppColors.error.withValues(alpha: 0.2),
          child: Icon(
            slot.isAvailable ? Icons.check : Icons.close,
            color: slot.isAvailable ? AppColors.primary : AppColors.error,
          ),
        ),
        title: Text(
          '${Formatters.formatTime(slot.startTime)} - ${Formatters.formatTime(slot.endTime)}',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete, color: AppColors.error),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// One direction of a mixed blocked-dates change.
///
/// An icon per line so the direction is not carried by a single word buried in
/// a sentence — §13's rule against meaning by one channel alone, applied to
/// wording rather than colour.
class _DeltaLine extends StatelessWidget {
  const _DeltaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: AppTheme.iconS, color: AppColors.textSecondary),
        const SizedBox(width: AppTheme.spacingS),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
