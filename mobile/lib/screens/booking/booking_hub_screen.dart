import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/booking_duration.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/rebook.dart';
import '../../core/utils/salon_time.dart';
import '../../models/provider.dart' as models;
import '../../models/service.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/booking/length_variant_selector.dart';

class BookingDraft {
  final String providerId;
  final List<String> serviceIds;
  final String? artistId;
  final DateTime? dateTime;

  /// Chosen hair length ('court'/'moyen'/'long') when a selected service
  /// declares duration variants; otherwise null.
  final String? lengthVariant;

  const BookingDraft({
    required this.providerId,
    this.serviceIds = const [],
    this.artistId,
    this.dateTime,
    this.lengthVariant,
  });

  BookingDraft copyWith({
    List<String>? serviceIds,
    String? artistId,
    bool clearArtistId = false,
    DateTime? dateTime,
    bool clearDateTime = false,
    String? lengthVariant,
    bool clearLengthVariant = false,
  }) {
    return BookingDraft(
      providerId: providerId,
      serviceIds: serviceIds ?? this.serviceIds,
      artistId: clearArtistId ? null : (artistId ?? this.artistId),
      dateTime: clearDateTime ? null : (dateTime ?? this.dateTime),
      lengthVariant:
          clearLengthVariant ? null : (lengthVariant ?? this.lengthVariant),
    );
  }
}

enum _HubEntryPoint { services, artist, dateTime }

enum _HubSection { services, artist, dateTime }

class BookingHubScreen extends StatefulWidget {
  final String providerId;

  /// Pre-fill (used by rebook): the services + stylist to start from.
  final List<String> initialServiceIds;
  final String? initialArtistId;

  const BookingHubScreen({
    super.key,
    required this.providerId,
    this.initialServiceIds = const [],
    this.initialArtistId,
  });

  @override
  State<BookingHubScreen> createState() => _BookingHubScreenState();
}

class _BookingHubScreenState extends State<BookingHubScreen> {
  late BookingDraft _draft;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _servicesKey = GlobalKey();
  final GlobalKey _artistKey = GlobalKey();
  final GlobalKey _dateTimeKey = GlobalKey();

  _HubEntryPoint? _entryPoint;
  _HubSection _activeSection = _HubSection.services;

  // Distinguish "not picked yet" vs "picked 'no preference'".
  bool _artistChosen = false;

  DateTime _selectedDate = salonToday();
  List<DateTime> _availableSlotsForSelectedDate = const [];
  bool _isLoadingSlots = false;
  int _slotsRequestId = 0;

  @override
  void initState() {
    super.initState();
    final prefilled = widget.initialServiceIds.isNotEmpty;
    _draft = BookingDraft(
      providerId: widget.providerId,
      serviceIds: widget.initialServiceIds,
      artistId: widget.initialArtistId,
    );
    _artistChosen = widget.initialArtistId != null;
    if (prefilled) {
      // Rebook: land directly on the date/time picker.
      _activeSection = _HubSection.dateTime;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final providerProvider =
          Provider.of<ProviderProvider>(context, listen: false);
      await providerProvider.loadProviderById(widget.providerId);
      if (!mounted || !prefilled) return;

      final p = providerProvider.selectedProvider;
      if (p == null) return;

      // Drop any services/stylist that no longer exist on this provider.
      final selection = sanitizeRebookSelection(
        serviceIds: widget.initialServiceIds,
        artistId: widget.initialArtistId,
        availableServiceIds: p.services.map((s) => s.id).toSet(),
        availableArtistIds: p.artists.map((a) => a.id).toSet(),
      );
      setState(() {
        _draft = _draft.copyWith(
          serviceIds: selection.serviceIds,
          artistId: selection.artistId,
          clearArtistId: selection.artistId == null,
        );
        _artistChosen = selection.artistId != null;
      });

      if (selection.serviceIds.isNotEmpty) {
        final appointmentProvider =
            Provider.of<AppointmentProvider>(context, listen: false);
        await _loadSlotsForSelectedDate(
          appointmentProvider: appointmentProvider,
          p: p,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<Service> _selectedServices(models.Provider p) =>
      p.services.where((s) => _draft.serviceIds.contains(s.id)).toList();

  int _totalDurationMinutes(models.Provider p) {
    if (_draft.serviceIds.isEmpty) return 0;
    return totalBookingDuration(_selectedServices(p), _draft.lengthVariant);
  }

  double _totalPrice(models.Provider p) {
    if (_draft.serviceIds.isEmpty) return 0;
    return p.services
        .where((s) => _draft.serviceIds.contains(s.id))
        .fold<double>(0, (sum, s) => sum + s.price);
  }

  String _artistLabel(models.Provider p) {
    if (_draft.artistId == null) return 'Pas de préférence';
    final a = p.artists.where((a) => a.id == _draft.artistId).toList();
    return a.isEmpty ? 'Pas de préférence' : a.first.name;
  }

  String _servicesLabel(models.Provider p) {
    if (_draft.serviceIds.isEmpty) return 'Choisir';
    final services = p.services.where((s) => _draft.serviceIds.contains(s.id));
    final count = services.length;
    if (count == 1) return services.first.name;
    return '$count services';
  }

  String _dateTimeLabel() {
    final dt = _draft.dateTime;
    if (dt == null) return 'Choisir';
    return '${Formatters.formatDateShort(dt)} • ${Formatters.formatTime(dt)}';
  }

  bool _artistCanDoServices(
      models.Provider p, String artistId, List<String> serviceIds) {
    final selectedServices =
        p.services.where((s) => serviceIds.contains(s.id)).toList();
    if (selectedServices.isEmpty) return true;
    final unrestricted = selectedServices.any((s) => s.artistIds.isEmpty);
    if (unrestricted) return true;
    return selectedServices.every((s) => s.artistIds.contains(artistId));
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.08,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  _HubSection _nextSection(models.Provider p) {
    final hasArtists = p.artists.isNotEmpty;
    final artistSatisfied = !hasArtists || _artistChosen;

    switch (_entryPoint) {
      case _HubEntryPoint.services:
        if (_draft.serviceIds.isEmpty) return _HubSection.services;
        if (hasArtists && !artistSatisfied) return _HubSection.artist;
        if (_draft.dateTime == null) return _HubSection.dateTime;
        return _HubSection.dateTime;
      case _HubEntryPoint.artist:
        if (hasArtists && !artistSatisfied) return _HubSection.artist;
        if (_draft.serviceIds.isEmpty) return _HubSection.services;
        if (_draft.dateTime == null) return _HubSection.dateTime;
        return _HubSection.dateTime;
      case _HubEntryPoint.dateTime:
        if (_draft.dateTime == null) return _HubSection.dateTime;
        if (_draft.serviceIds.isEmpty) return _HubSection.services;
        if (hasArtists && !artistSatisfied) return _HubSection.artist;
        return _HubSection.artist;
      case null:
        // Default order until user starts.
        if (_draft.serviceIds.isNotEmpty) return _HubSection.artist;
        return _HubSection.services;
    }
  }

  void _setEntryPointIfNeeded(_HubEntryPoint ep) {
    _entryPoint ??= ep;
  }

  void _activateSection(_HubSection section) {
    if (_activeSection == section) return;
    setState(() => _activeSection = section);
  }

  Future<void> _advance(models.Provider p) async {
    final next = _nextSection(p);
    _activateSection(next);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (!mounted) return;
    if (next == _HubSection.services) {
      await _scrollTo(_servicesKey);
    } else if (next == _HubSection.artist) {
      await _scrollTo(_artistKey);
    } else {
      await _scrollTo(_dateTimeKey);
    }
  }

  Future<void> _loadSlotsForSelectedDate({
    required AppointmentProvider appointmentProvider,
    required models.Provider p,
  }) async {
    final reqId = ++_slotsRequestId;
    setState(() => _isLoadingSlots = true);

    final duration =
        _draft.serviceIds.isNotEmpty ? _totalDurationMinutes(p) : 30;
    final serviceIds = _draft.serviceIds.isNotEmpty ? _draft.serviceIds : null;

    final slots = await appointmentProvider.getAvailableTimeSlots(
      providerId: widget.providerId,
      date: _selectedDate,
      serviceIds: serviceIds,
      artistId: _draft.artistId,
      durationMinutes: duration,
    );

    if (!mounted || reqId != _slotsRequestId) return;
    setState(() {
      _availableSlotsForSelectedDate = slots;
      _isLoadingSlots = false;
    });
  }

  Future<bool> _validateSelectedDateTime({
    required AppointmentProvider appointmentProvider,
    required models.Provider p,
  }) async {
    final dt = _draft.dateTime;
    if (dt == null) return true;

    final date = DateTime(dt.year, dt.month, dt.day);
    final duration =
        _draft.serviceIds.isNotEmpty ? _totalDurationMinutes(p) : 30;
    final serviceIds = _draft.serviceIds.isNotEmpty ? _draft.serviceIds : null;

    final slots = await appointmentProvider.getAvailableTimeSlots(
      providerId: widget.providerId,
      date: date,
      serviceIds: serviceIds,
      artistId: _draft.artistId,
      durationMinutes: duration,
    );

    final ok = slots.any((s) => s.isAtSameMomentAs(dt));
    if (!mounted) return ok;
    if (!ok) {
      setState(() {
        _draft = _draft.copyWith(clearDateTime: true);
      });
    }
    return ok;
  }

  Future<DateTime?> _findEarliestSlot({
    required AppointmentProvider appointmentProvider,
    required models.Provider p,
    required int daysAhead,
  }) async {
    final duration = _totalDurationMinutes(p);
    final serviceIds = _draft.serviceIds;
    if (serviceIds.isEmpty) return null;

    final startDay = salonToday();
    for (var i = 0; i <= daysAhead; i++) {
      final d = startDay.add(Duration(days: i));
      final slots = await appointmentProvider.getAvailableTimeSlots(
        providerId: widget.providerId,
        date: d,
        serviceIds: serviceIds,
        artistId: _draft.artistId,
        durationMinutes: duration,
      );
      if (slots.isNotEmpty) return slots.first;
    }
    return null;
  }

  Future<void> _confirm(models.Provider p) async {
    if (_draft.serviceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez au moins un service')),
      );
      return;
    }
    if (_draft.dateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez une date et une heure')),
      );
      return;
    }

    final qs = <String, String>{
      'providerId': widget.providerId,
      'serviceIds': _draft.serviceIds.join(','),
      'dateTime': _draft.dateTime!.toIso8601String(),
      if (_draft.artistId != null) 'artistId': _draft.artistId!,
      if (_draft.lengthVariant != null) 'lengthVariant': _draft.lengthVariant!,
    };

    try {
      await context.push(
        Uri(path: '/booking/confirm', queryParameters: qs).toString(),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir la confirmation')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Réserver'),
      ),
      body: Consumer2<ProviderProvider, AppointmentProvider>(
        builder: (context, providerProvider, appointmentProvider, _) {
          if (providerProvider.isLoading &&
              providerProvider.selectedProvider == null) {
            return const Center(child: LoadingIndicator());
          }

          final p = providerProvider.selectedProvider;
          if (p == null) {
            return Center(
              child: Text(
                providerProvider.error ?? 'Salon introuvable',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            );
          }

          final totalPrice = _totalPrice(p);
          final totalDuration = _totalDurationMinutes(p);
          final canConfirm =
              _draft.serviceIds.isNotEmpty && _draft.dateTime != null;

          return Padding(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppTheme.spacingM),
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusXL),
                          boxShadow: AppTheme.elevation1,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: AppTextStyles.titleLarge),
                            const SizedBox(height: 4),
                            Text(
                              p.address,
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingM),

                      // SERVICES
                      _HubSectionCard(
                        key: _servicesKey,
                        icon: Icons.list_alt,
                        title: 'Services',
                        value: _servicesLabel(p),
                        expanded: _activeSection == _HubSection.services,
                        onHeaderTap: () {
                          _activateSection(_HubSection.services);
                          _scrollTo(_servicesKey);
                        },
                        child: Column(
                          children: [
                            ...p.services.map((s) {
                              final selected = _draft.serviceIds.contains(s.id);
                              return _SelectableRow(
                                title: s.name,
                                subtitle: s.durationVariants.isNotEmpty
                                    ? '${Formatters.formatPriceRange(s.price, s.priceMax)} • durée selon la longueur'
                                    : '${Formatters.formatDuration(s.durationMinutes)} • ${Formatters.formatPriceRange(s.price, s.priceMax)}',
                                selected: selected,
                                onTap: () async {
                                  _setEntryPointIfNeeded(
                                      _HubEntryPoint.services);
                                  final nextIds =
                                      List<String>.from(_draft.serviceIds);
                                  if (selected) {
                                    nextIds.remove(s.id);
                                  } else {
                                    nextIds.add(s.id);
                                  }

                                  setState(() {
                                    _draft =
                                        _draft.copyWith(serviceIds: nextIds);
                                    // If currently-selected artist can't do selected services, force re-pick.
                                    if (_draft.artistId != null &&
                                        !_artistCanDoServices(
                                            p, _draft.artistId!, nextIds)) {
                                      _draft =
                                          _draft.copyWith(clearArtistId: true);
                                      _artistChosen = false;
                                    }
                                    // Keep the hair-length choice valid for the
                                    // new selection.
                                    final selected = _selectedServices(p);
                                    if (!bookingHasVariants(selected)) {
                                      _draft = _draft.copyWith(
                                          clearLengthVariant: true);
                                    } else if (_draft.lengthVariant == null ||
                                        !availableLengthVariants(selected)
                                            .contains(_draft.lengthVariant)) {
                                      _draft = _draft.copyWith(
                                          lengthVariant:
                                              defaultLengthVariant(selected));
                                    }
                                  });

                                  // If user picked time first, keep time if still valid; otherwise clear.
                                  await _validateSelectedDateTime(
                                    appointmentProvider: appointmentProvider,
                                    p: p,
                                  );

                                  // If user started with artist first, auto-pick nearest time once services exist.
                                  if (_entryPoint == _HubEntryPoint.artist &&
                                      _artistChosen &&
                                      _draft.serviceIds.isNotEmpty &&
                                      _draft.dateTime == null) {
                                    final earliest = await _findEarliestSlot(
                                      appointmentProvider: appointmentProvider,
                                      p: p,
                                      daysAhead: 14,
                                    );
                                    if (!mounted) return;
                                    if (earliest != null) {
                                      setState(() {
                                        _draft =
                                            _draft.copyWith(dateTime: earliest);
                                        _selectedDate = DateTime(
                                          earliest.year,
                                          earliest.month,
                                          earliest.day,
                                        );
                                      });
                                    }
                                  }

                                  await _advance(p);

                                  // Refresh slots if time section is next/active.
                                  if (_activeSection == _HubSection.dateTime) {
                                    await _loadSlotsForSelectedDate(
                                      appointmentProvider: appointmentProvider,
                                      p: p,
                                    );
                                  }
                                },
                              );
                            }),
                            if (p.services.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                    top: AppTheme.spacingS),
                                child: Text(
                                  'Aucun service disponible',
                                  style: AppTextStyles.bodySmall
                                      .copyWith(color: AppColors.textSecondary),
                                ),
                              ),
                            if (bookingHasVariants(_selectedServices(p))) ...[
                              const SizedBox(height: AppTheme.spacingM),
                              LengthVariantSelector(
                                available: availableLengthVariants(
                                    _selectedServices(p)),
                                selected: _draft.lengthVariant,
                                durationFor: (length) => totalBookingDuration(
                                    _selectedServices(p), length),
                                onChanged: (length) async {
                                  setState(() => _draft =
                                      _draft.copyWith(lengthVariant: length));
                                  await _validateSelectedDateTime(
                                    appointmentProvider: appointmentProvider,
                                    p: p,
                                  );
                                  if (_activeSection == _HubSection.dateTime) {
                                    await _loadSlotsForSelectedDate(
                                      appointmentProvider: appointmentProvider,
                                      p: p,
                                    );
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingS),

                      // ARTIST
                      _HubSectionCard(
                        key: _artistKey,
                        icon: Icons.person_outline,
                        title: 'Spécialiste',
                        value: _artistLabel(p),
                        expanded: _activeSection == _HubSection.artist,
                        onHeaderTap: () {
                          _activateSection(_HubSection.artist);
                          _scrollTo(_artistKey);
                        },
                        child: Column(
                          children: [
                            _SelectableRow(
                              title: 'Pas de préférence',
                              subtitle: 'Le salon choisit pour vous',
                              selected:
                                  _artistChosen && _draft.artistId == null,
                              onTap: () async {
                                _setEntryPointIfNeeded(_HubEntryPoint.artist);
                                setState(() {
                                  _artistChosen = true;
                                  _draft = _draft.copyWith(clearArtistId: true);
                                });
                                await _validateSelectedDateTime(
                                  appointmentProvider: appointmentProvider,
                                  p: p,
                                );
                                await _advance(p);
                                if (_activeSection == _HubSection.dateTime) {
                                  await _loadSlotsForSelectedDate(
                                    appointmentProvider: appointmentProvider,
                                    p: p,
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 6),
                            ...p.artists.map((a) {
                              final selected =
                                  _artistChosen && _draft.artistId == a.id;
                              final canDoSelectedServices =
                                  _draft.serviceIds.isEmpty
                                      ? true
                                      : _artistCanDoServices(
                                          p, a.id, _draft.serviceIds);
                              return Opacity(
                                opacity: canDoSelectedServices ? 1.0 : 0.45,
                                child: _SelectableRow(
                                  title: a.name,
                                  subtitle: a.specialization ?? 'Spécialiste',
                                  selected: selected,
                                  enabled: canDoSelectedServices,
                                  onTap: () async {
                                    if (!canDoSelectedServices) return;
                                    _setEntryPointIfNeeded(
                                        _HubEntryPoint.artist);
                                    setState(() {
                                      _artistChosen = true;
                                      _draft = _draft.copyWith(artistId: a.id);
                                    });

                                    await _validateSelectedDateTime(
                                      appointmentProvider: appointmentProvider,
                                      p: p,
                                    );

                                    // If user started with artist first AND already has services, auto-pick earliest.
                                    if (_entryPoint == _HubEntryPoint.artist &&
                                        _draft.serviceIds.isNotEmpty &&
                                        _draft.dateTime == null) {
                                      final earliest = await _findEarliestSlot(
                                        appointmentProvider:
                                            appointmentProvider,
                                        p: p,
                                        daysAhead: 14,
                                      );
                                      if (!mounted) return;
                                      if (earliest != null) {
                                        setState(() {
                                          _draft = _draft.copyWith(
                                              dateTime: earliest);
                                          _selectedDate = DateTime(
                                            earliest.year,
                                            earliest.month,
                                            earliest.day,
                                          );
                                        });
                                      }
                                    }

                                    await _advance(p);
                                    if (_activeSection ==
                                        _HubSection.dateTime) {
                                      await _loadSlotsForSelectedDate(
                                        appointmentProvider:
                                            appointmentProvider,
                                        p: p,
                                      );
                                    }
                                  },
                                ),
                              );
                            }),
                            if (p.artists.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                    top: AppTheme.spacingS),
                                child: Text(
                                  'Aucun spécialiste à sélectionner',
                                  style: AppTextStyles.bodySmall
                                      .copyWith(color: AppColors.textSecondary),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingS),

                      // DATE/TIME
                      _HubSectionCard(
                        key: _dateTimeKey,
                        icon: Icons.calendar_today,
                        title: 'Date et heure',
                        value: _dateTimeLabel(),
                        expanded: _activeSection == _HubSection.dateTime,
                        onHeaderTap: () async {
                          _activateSection(_HubSection.dateTime);
                          await _scrollTo(_dateTimeKey);
                          await _loadSlotsForSelectedDate(
                            appointmentProvider: appointmentProvider,
                            p: p,
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _DatePickerRow(
                              date: _selectedDate,
                              onTap: () async {
                                _setEntryPointIfNeeded(_HubEntryPoint.dateTime);
                                final initial = DateTime(
                                  _selectedDate.year,
                                  _selectedDate.month,
                                  _selectedDate.day,
                                );
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: initial,
                                  firstDate: salonToday(),
                                  lastDate: salonToday()
                                      .add(const Duration(days: 365)),
                                );
                                if (!mounted || picked == null) return;
                                setState(() => _selectedDate = picked);
                                await _loadSlotsForSelectedDate(
                                  appointmentProvider: appointmentProvider,
                                  p: p,
                                );
                              },
                            ),
                            const SizedBox(height: AppTheme.spacingS),
                            if (_isLoadingSlots)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(child: LoadingIndicator()),
                              )
                            else if (_availableSlotsForSelectedDate.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Text(
                                  'Aucun créneau disponible',
                                  style: AppTextStyles.bodySmall
                                      .copyWith(color: AppColors.textSecondary),
                                ),
                              )
                            else
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children:
                                    _availableSlotsForSelectedDate.map((slot) {
                                  final selected = _draft.dateTime != null &&
                                      _draft.dateTime!.isAtSameMomentAs(slot);
                                  return ChoiceChip(
                                    label: Text(Formatters.formatTime(slot)),
                                    selected: selected,
                                    onSelected: (_) async {
                                      _setEntryPointIfNeeded(
                                          _HubEntryPoint.dateTime);
                                      setState(() => _draft =
                                          _draft.copyWith(dateTime: slot));
                                      await _advance(p);
                                    },
                                    selectedColor: AppColors.primary
                                        .withValues(alpha: 0.15),
                                    labelStyle:
                                        AppTextStyles.bodySmall.copyWith(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.textPrimary,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                      side: BorderSide(
                                        color: selected
                                            ? AppColors.primary
                                            : AppColors.border,
                                      ),
                                    ),
                                    backgroundColor: AppColors.secondary,
                                  );
                                }).toList(),
                              ),
                            if (_entryPoint == _HubEntryPoint.artist &&
                                _artistChosen &&
                                _draft.serviceIds.isNotEmpty &&
                                _draft.dateTime != null) ...[
                              const SizedBox(height: AppTheme.spacingS),
                              Text(
                                'Prochain créneau: ${Formatters.formatDateShort(_draft.dateTime!)} • ${Formatters.formatTime(_draft.dateTime!)}',
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingM),
                    ],
                  ),
                ),

                // SUMMARY (sticky)
                Container(
                  padding: const EdgeInsets.all(AppTheme.spacingM),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                    boxShadow: AppTheme.elevation2,
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total', style: AppTextStyles.titleMedium),
                          Text(
                            Formatters.formatCurrency(totalPrice),
                            style: AppTextStyles.titleLarge
                                .copyWith(color: AppColors.primary),
                          ),
                        ],
                      ),
                      if (totalDuration > 0) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Durée: ${Formatters.formatDuration(totalDuration)}',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                      if (!_artistChosen && p.artists.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Spécialiste optionnel (vous pouvez laisser “Pas de préférence”)',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppTheme.spacingM),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: canConfirm ? () => _confirm(p) : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.secondary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLarge),
                            ),
                          ),
                          child: const Text('Confirmer'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HubSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool expanded;
  final VoidCallback onHeaderTap;
  final Widget child;

  const _HubSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.expanded,
    required this.onHeaderTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        border:
            Border.all(color: expanded ? AppColors.primary : AppColors.border),
        boxShadow: AppTheme.elevation1,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onHeaderTap,
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Icon(icon, color: AppColors.textPrimary),
                ),
                const SizedBox(width: AppTheme.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: const Icon(Icons.chevron_right,
                      color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOut,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: AppTheme.spacingM),
                    child: child,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SelectableRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _SelectableRow({
    required this.title,
    this.subtitle,
    required this.selected,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.textPrimary : AppColors.textTertiary;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border),
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check, size: 18, color: AppColors.primary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyMedium.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatePickerRow extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;

  const _DatePickerRow({
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(color: AppColors.border),
          color: AppColors.secondary,
        ),
        child: Row(
          children: [
            const Icon(Icons.event, color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                Formatters.formatDate(date),
                style: AppTextStyles.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
