import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/booking_duration.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/salon_time.dart';
import '../../models/service.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/locality_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/booking/length_variant_selector.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/salon_time_hint.dart';

class DateTimeSelectionScreen extends StatefulWidget {
  final String providerId;
  final List<String> serviceIds;
  final String? artistId;
  final bool returnToHub;
  final DateTime? initialDateTime;
  final int? durationMinutes;

  const DateTimeSelectionScreen({
    super.key,
    required this.providerId,
    required this.serviceIds,
    this.artistId,
    this.returnToHub = false,
    this.initialDateTime,
    this.durationMinutes,
  });

  @override
  State<DateTimeSelectionScreen> createState() =>
      _DateTimeSelectionScreenState();
}

class _DateTimeSelectionScreenState extends State<DateTimeSelectionScreen> {
  /// The VIEWED salon's timezone (multi-pays MP2) — null until the provider
  /// loads (the Abidjan fallback keeps the first frame correct).
  String? get _tz =>
      context.read<ProviderProvider>().selectedProvider?.timezone;

  /// The salon "today" as a NAIVE date — table_calendar compares its naive
  /// day cells field-to-field (never `.toUtc()` these).
  DateTime _salonTodayNaive() {
    final s = salonNow(tz: _tz);
    return DateTime(s.year, s.month, s.day);
  }

  static DateTime _todayNaiveDefault() {
    final s = salonNow();
    return DateTime(s.year, s.month, s.day);
  }

  DateTime _selectedDate = _todayNaiveDefault();
  DateTime? _selectedTime;
  List<DateTime> _availableSlots = [];
  bool _loadingSlots = true;
  String? _lengthVariant;

  @override
  void initState() {
    super.initState();
    if (widget.initialDateTime != null) {
      // Prefill reads the instant as SALON wall-clock (salon_time.dart).
      // The provider isn't loaded yet — the tz getter falls back to
      // Abidjan; the slot reload after load() re-anchors everything.
      final dt = toSalonTime(widget.initialDateTime!, tz: _tz);
      _selectedDate = DateTime(dt.year, dt.month, dt.day);
      _selectedTime = salonDateTime(dt.year, dt.month, dt.day,
          hour: dt.hour, minute: dt.minute, tz: _tz);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(context.read<LocalityProvider>().ensureLoaded());
      await Provider.of<ProviderProvider>(context, listen: false)
          .loadProviderById(widget.providerId);
      if (!mounted) return;
      // Default the hair length once we know the services (drives slot length).
      final services = _selectedServices();
      if (bookingHasVariants(services) && _lengthVariant == null) {
        _lengthVariant = defaultLengthVariant(services);
      }
      await _loadAvailableSlots();
    });
  }

  List<Service> _selectedServices() {
    final p =
        Provider.of<ProviderProvider>(context, listen: false).selectedProvider;
    if (p == null || widget.serviceIds.isEmpty) return const [];
    return p.services.where((s) => widget.serviceIds.contains(s.id)).toList();
  }

  Future<void> _loadAvailableSlots() async {
    setState(() => _loadingSlots = true);
    final services = _selectedServices();
    final durationMinutes = widget.durationMinutes ??
        (services.isEmpty
            ? 30
            : totalBookingDuration(services, _lengthVariant));
    final provider = Provider.of<AppointmentProvider>(context, listen: false);
    final slots = await provider.getAvailableTimeSlots(
      providerId: widget.providerId,
      date: _selectedDate,
      serviceIds: widget.serviceIds.isEmpty ? null : widget.serviceIds,
      artistId: widget.artistId,
      durationMinutes: durationMinutes,
    );
    setState(() {
      _availableSlots = slots;
      _loadingSlots = false;
      // Keep the previously selected time if it is still available, otherwise reset.
      if (_selectedTime != null) {
        final keep = _availableSlots.any((dt) =>
            dt.year == _selectedTime!.year &&
            dt.month == _selectedTime!.month &&
            dt.day == _selectedTime!.day &&
            dt.hour == _selectedTime!.hour &&
            dt.minute == _selectedTime!.minute);
        if (!keep) _selectedTime = null;
      }
    });
  }

  void _onDateSelected(DateTime date, DateTime focusedDate) {
    // Reject days before the SALON's today (naive-vs-naive compare).
    if (date.isBefore(_salonTodayNaive())) {
      return;
    }
    setState(() {
      _selectedDate = date;
      _selectedTime = null;
    });
    _loadAvailableSlots();
  }

  void _handleContinue() {
    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner une heure')),
      );
      return;
    }

    // The chosen wall-clock IS salon time — serializes with a Z.
    final dateTime = salonDateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      hour: _selectedTime!.hour,
      minute: _selectedTime!.minute,
      tz: _tz,
    );

    if (widget.returnToHub) {
      context.pop<DateTime>(dateTime);
      return;
    }

    final serviceIds = widget.serviceIds.join(',');
    final artistParam =
        widget.artistId != null ? '&artistId=${widget.artistId}' : '';
    final lengthParam =
        _lengthVariant != null ? '&lengthVariant=$_lengthVariant' : '';
    context.push(
      '/booking/confirm?providerId=${widget.providerId}&serviceIds=$serviceIds&dateTime=${dateTime.toIso8601String()}$artistParam$lengthParam',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Date et heure'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bookingHasVariants(
                      context.watch<ProviderProvider>().selectedProvider == null
                          ? const []
                          : _selectedServices())) ...[
                    LengthVariantSelector(
                      available: availableLengthVariants(_selectedServices()),
                      selected: _lengthVariant,
                      durationFor: (l) =>
                          totalBookingDuration(_selectedServices(), l),
                      onChanged: (l) {
                        setState(() => _lengthVariant = l);
                        _loadAvailableSlots();
                      },
                    ),
                    const SizedBox(height: AppTheme.spacingM),
                  ],
                  // Calendar
                  TableCalendar(
                    firstDay: _salonTodayNaive(),
                    lastDay: _salonTodayNaive().add(const Duration(days: 90)),
                    focusedDay: _selectedDate,
                    // The « today » ring follows the SALON's today.
                    currentDay: _salonTodayNaive(),
                    selectedDayPredicate: (day) {
                      return day.year == _selectedDate.year &&
                          day.month == _selectedDate.month &&
                          day.day == _selectedDate.day;
                    },
                    onDaySelected: _onDateSelected,
                    calendarStyle: const CalendarStyle(
                      selectedDecoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      todayDecoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                      ),
                      outsideDaysVisible: false,
                    ),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  // Time Slots
                  const Text(
                    'Heures disponibles',
                    style: AppTextStyles.titleLarge,
                  ),
                  SalonTimeHint(
                    tz: _tz,
                    countryLabel: context.watch<LocalityProvider>().countryName(
                          context
                              .read<ProviderProvider>()
                              .selectedProvider
                              ?.countryCode,
                        ),
                    padding: const EdgeInsets.only(top: AppTheme.spacingXS),
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  if (_loadingSlots)
                    const Center(child: LoadingIndicator())
                  else if (_availableSlots.isEmpty)
                    Center(
                      child: Text(
                        'Aucun créneau disponible pour cette date',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableSlots.map((slot) {
                        final isSelected = _selectedTime != null &&
                            _selectedTime!.hour == slot.hour &&
                            _selectedTime!.minute == slot.minute;

                        return GestureDetector(
                          onTap: () => setState(() => _selectedTime = slot),
                          child: Container(
                            width: 80,
                            height: 48,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.secondary,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMedium),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.borderStrong,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                Formatters.formatTime(
                                    toSalonTime(slot, tz: _tz)),
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: isSelected
                                      ? AppColors.secondary
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
          // Continue Button
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              boxShadow: AppTheme.elevation3,
            ),
            child: AppButton(
              text: 'Continuer',
              onPressed: _selectedTime == null ? null : _handleContinue,
            ),
          ),
        ],
      ),
    );
  }
}
