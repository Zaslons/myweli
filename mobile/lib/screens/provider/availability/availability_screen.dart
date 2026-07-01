import 'package:flutter/material.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/availability.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_availability_provider.dart';
import '../../../widgets/provider/weekly_hours_editor.dart';

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  String _resolvedProviderId(BuildContext context) {
    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    return authProvider.provider?.providerId ?? authProvider.provider?.id ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.provider != null) {
        final availabilityProvider =
            Provider.of<ProAvailabilityProvider>(context, listen: false);
        availabilityProvider.loadAvailability(_resolvedProviderId(context));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Disponibilité'),
      ),
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
                style: AppTextStyles.bodyLarge
                    .copyWith(color: AppColors.textSecondary),
              ),
            );
          }

          return BrandRefresh(
            onRefresh: () async {
              if (authProvider.provider != null) {
                await availabilityProvider
                    .loadAvailability(_resolvedProviderId(context));
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppTheme.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 24),
                  Text(
                    'Pauses',
                    style: AppTextStyles.titleLarge
                        .copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Une pause récurrente par jour (ex. déjeuner). '
                    'Aucun créneau ne sera proposé pendant ces heures.',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 24),
                  Text(
                    'Horaires de travail',
                    style: AppTextStyles.titleLarge
                        .copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 16),
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
                          _resolvedProviderId(context)),
                    );
                  }),
                  const SizedBox(height: 24),
                  Text(
                    'Dates bloquées',
                    style: AppTextStyles.titleLarge
                        .copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  if (availability.blockedDates.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(AppTheme.spacingM),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusLarge),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: AppColors.textSecondary),
                          const SizedBox(width: 12),
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
                    ...availability.blockedDates.map((date) => _BlockedDateCard(
                          date: date,
                          onRemove: () => _removeBlockedDate(
                            context,
                            date,
                            availability,
                            availabilityProvider,
                            _resolvedProviderId(context),
                          ),
                        )),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _showAddBlockedDateDialog(
                      context,
                      availability,
                      availabilityProvider,
                      _resolvedProviderId(context),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Bloquer une date'),
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
      'Dimanche'
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

  void _showAddBlockedDateDialog(
    BuildContext context,
    Availability availability,
    ProAvailabilityProvider provider,
    String providerId,
  ) async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (selectedDate != null && context.mounted) {
      final updatedBlockedDates = List<DateTime>.from(availability.blockedDates)
        ..add(
            DateTime(selectedDate.year, selectedDate.month, selectedDate.day));
      final updatedAvailability =
          availability.copyWith(blockedDates: updatedBlockedDates);
      await provider.updateAvailability(providerId, updatedAvailability);
      if (context.mounted && provider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.error!),
            backgroundColor: AppColors.error,
          ),
        );
      }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error!),
          backgroundColor: AppColors.error,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error!),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _removeBlockedDate(
    BuildContext context,
    DateTime date,
    Availability availability,
    ProAvailabilityProvider provider,
    String providerId,
  ) async {
    final updatedBlockedDates = List<DateTime>.from(availability.blockedDates)
      ..removeWhere((d) =>
          d.year == date.year && d.month == date.month && d.day == date.day);
    final updatedAvailability =
        availability.copyWith(blockedDates: updatedBlockedDates);
    await provider.updateAvailability(providerId, updatedAvailability);
    if (context.mounted && provider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error!),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
          Row(
            children: [
              const Icon(Icons.hourglass_bottom,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Temps de battement',
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Pause automatique entre deux rendez-vous (nettoyage, '
            'préparation). Les créneaux proposés aux clients en tiennent compte.',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
          style:
              AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimary),
        ),
        subtitle: timeSlots.isEmpty
            ? Text(
                'Fermé',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 4,
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
          icon: const Icon(Icons.edit),
          onPressed: onEdit,
        ),
      ),
    );
  }
}

class _BlockedDateCard extends StatelessWidget {
  final DateTime date;
  final VoidCallback onRemove;

  const _BlockedDateCard({
    required this.date,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingS),
      child: ListTile(
        leading: const Icon(Icons.block, color: AppColors.error),
        title: Text(
          Formatters.formatDate(date),
          style:
              AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
        ),
        trailing: IconButton(
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
        title: Text('Horaires - ${widget.dayName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addTimeSlot,
          ),
        ],
      ),
      body: Consumer<ProAvailabilityProvider>(
        builder: (context, provider, _) {
          final availability = provider.availability;
          if (availability == null) {
            return const Center(child: Text('Chargement...'));
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
                        const Icon(Icons.access_time,
                            size: 48, color: AppColors.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          'Aucun créneau horaire',
                          style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
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
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: provider.isLoading
                      ? null
                      : () => _saveSchedule(availability, provider),
                  child: provider.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: BrandLoader(size: 20, fast: true),
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

    final pickedStart = await showTimePicker(
      context: context,
      initialTime: startTime ?? const TimeOfDay(hour: 9, minute: 0),
    );

    if (pickedStart == null || !mounted) return;

    final pickedEnd = await showTimePicker(
      context: context,
      initialTime: endTime ??
          TimeOfDay(hour: pickedStart.hour + 1, minute: pickedStart.minute),
    );

    if (pickedEnd == null || !mounted) return;

    final now = DateTime.now();
    final startDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      pickedStart.hour,
      pickedStart.minute,
    );
    final endDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      pickedEnd.hour,
      pickedEnd.minute,
    );

    if (endDateTime.isBefore(startDateTime) ||
        endDateTime.isAtSameMomentAs(startDateTime)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('L\'heure de fin doit être après l\'heure de début'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

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
      Availability availability, ProAvailabilityProvider provider) async {
    final updatedSchedule =
        Map<int, List<TimeSlot>>.from(availability.weeklySchedule);
    updatedSchedule[widget.dayIndex] = _slots;

    final updatedAvailability =
        availability.copyWith(weeklySchedule: updatedSchedule);

    final success = await provider.updateAvailability(
        widget.providerId, updatedAvailability);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Horaires enregistrés'),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.error ?? 'Erreur lors de l\'enregistrement'),
            backgroundColor: AppColors.error,
          ),
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
          style:
              AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: AppColors.error),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
