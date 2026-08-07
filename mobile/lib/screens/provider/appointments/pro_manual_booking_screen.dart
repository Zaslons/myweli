import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/booking_horizons.dart';
import '../../../core/forms/field_errors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/salon_time.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/pro_appointment_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_service_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/inline_feedback.dart';
import '../../../widgets/common/label_value_row.dart';
import '../../../widgets/common/loading_indicator.dart';
import '../../../widgets/common/myweli_date_picker.dart';
import '../../../widgets/common/myweli_time_picker.dart';

class ProManualBookingScreen extends StatefulWidget {
  const ProManualBookingScreen({
    super.key,
    this.initialClientName,
    this.initialClientPhone,
    this.initialDateTime,
    this.initialArtistId,
  });

  /// Prefill from the client card (module clients C1c) or a journal gap slot
  /// (module journal J1b — « Libre » row prefills the start time AND the
  /// filtered artist — audit 1.11).
  final String? initialClientName;
  final String? initialClientPhone;
  final DateTime? initialDateTime;
  final String? initialArtistId;

  @override
  State<ProManualBookingScreen> createState() => _ProManualBookingScreenState();
}

class _ProManualBookingScreenState extends State<ProManualBookingScreen> {
  final Set<String> _selected = {};
  // Seeds + the recombined instant are the ACTIVE SALON's wall-clock
  // (salon_time.dart) — tz from ProAuthProvider, seeded in initState.
  DateTime? _date;
  TimeOfDay? _time;
  late final _phone = TextEditingController(
    text: widget.initialClientPhone ?? '',
  );
  late final _name = TextEditingController(
    text: widget.initialClientName ?? '',
  );
  final _note = TextEditingController();
  bool _anonymous = false;
  bool _sendSms = true;
  bool _submitting = false;
  String? _providerId;

  String? get _tz => context.read<ProAuthProvider>().salonTimezone;

  @override
  void initState() {
    super.initState();
    final dt = widget.initialDateTime;
    if (dt != null) {
      final wall = toSalonTime(dt, tz: _tz);
      _date = wall;
      _time = TimeOfDay.fromDateTime(wall);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = context.read<ProAuthProvider>().activeSalonId;
      if (id != null && id.isNotEmpty) {
        _providerId = id;
        context.read<ProServiceProvider>().loadServices(id);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _phoneFocus.dispose();
    _phone.dispose();
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime? get _dateTime {
    if (_date == null || _time == null) return null;
    return salonDateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      hour: _time!.hour,
      minute: _time!.minute,
      tz: _tz,
    );
  }

  /// A7/§14 rule 5 — work in progress only. The three content clauses moved
  /// into `_submit`, which now answers instead of the button going dead.
  bool get _canSubmit => !_submitting;

  /// The selection faults (services, date/time) have no field to sit under, so
  /// they land form-level. The phone DOES have one.
  String? _selectionError;
  late final _errors = FieldErrors({
    // The one field that really is typed as local digits — its formatter is
    // `digitsOnly`, so a `+` cannot even be entered.
    'phone': Validators.localPhoneNumber,
  });
  final _phoneFocus = FocusNode();

  /// The minute grid the time picker offers, so this screen's own lift lands on
  /// a value the picker would have shown.
  static const int _kMinuteStep = 5;

  /// The salon's now, as a wall-clock time, for the past-time floor.
  TimeOfDay get _floorNow {
    final now = salonNow(tz: _tz);
    return TimeOfDay(hour: now.hour, minute: now.minute);
  }

  bool _isToday(DateTime d) {
    final today = salonToday(tz: _tz);
    return d.year == today.year && d.month == today.month && d.day == today.day;
  }

  Future<void> _pickDate() async {
    final today = salonToday(tz: _tz);
    final picked = await showMyweliDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: today,
      lastDate: today.add(kManualBookingHorizon),
      today: today,
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      // **The floor is a property of the DAY, so changing the day re-applies
      // it.** These are two independent fields — this is the one site of the six
      // where date and time are not a chain — so the user can pick tomorrow at
      // 09:00 and *then* move the date to today, stranding the time in the past.
      // Lifting it here is what makes the invalid combination unreachable from
      // either order of filling the form.
      final t = _time;
      if (t != null && _isToday(picked)) {
        final floor = _floorNow;
        final floorMinutes = floor.hour * 60 + floor.minute;
        if (t.hour * 60 + t.minute < floorMinutes) {
          // **Snapped onto the picker's grid, not set to the raw clock.** The
          // first version assigned `_floorNow` directly, so moving the date to
          // today at 14:07 put « 14:07 » in the field — a value the 5-minute
          // picker would never have offered, and one the user never chose. The
          // picker's own lift snaps; this one has to agree with it.
          final lifted = snapUpToStep(floorMinutes, _kMinuteStep);
          _time = TimeOfDay(hour: lifted ~/ 60, minute: lifted % 60);
        }
      }
    });
  }

  Future<void> _pickTime() async {
    final d = _date;
    final picked = await showMyweliTimePicker(
      context: context,
      initialTime: _time ?? _floorNow,
      // Bounded only when the chosen day is today. With no date chosen yet there
      // is nothing to bound against, and `_pickDate` covers that order.
      minuteStep: _kMinuteStep,
      minTime: d != null && _isToday(d) ? _floorNow : null,
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit(double total) async {
    if (_selected.isEmpty) {
      setState(() => _selectionError = 'Choisissez au moins un service.');
      return;
    }
    final dt = _dateTime;
    if (dt == null) {
      setState(() => _selectionError = 'Choisissez une date et une heure.');
      return;
    }
    if (dt.isBefore(AppClock.now())) {
      // **A14b demoted this from validation to drift backstop, and did NOT
      // delete it.** Its old comment said it was reachable *"because the time
      // picker has no past-time constraint"*, and A14b gave the picker one
      // (`minTime`), plus a re-lift in `_pickDate` for the other fill order — so
      // no sequence of taps can now produce a past time.
      //
      // But the spec for this slice claimed the error state disappears, and that
      // was wrong: **the wall clock moves while the form is open.** Pick today at
      // 14:05 at 14:00, submit at 14:10, and this fires. A guard that is nearly
      // unreachable is still reachable, and deleting it would have traded a rare
      // field-level message for a server round-trip.
      setState(
        () => _selectionError = 'Choisissez une date et une heure à venir.',
      );
      return;
    }
    if (!_anonymous && !_errors.validate({'phone': _phone.text})) {
      setState(() => _selectionError = null);
      _phoneFocus.requestFocus();
      return;
    }
    setState(() {
      _selectionError = null;
      _errors.clear();
    });

    setState(() => _submitting = true);
    final provider = context.read<ProAppointmentProvider>();
    final ok = await provider.createManualBooking(
      providerId: _providerId!,
      serviceIds: _selected.toList(),
      appointmentDateTime: dt,
      clientName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      clientPhone: _anonymous ? null : _phone.text.trim(),
      notes: _note.text.trim().isEmpty ? null : _note.text.trim(),
      artistId: widget.initialArtistId,
      sendSmsInvite: _sendSms && !_anonymous && _phone.text.trim().isNotEmpty,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      AppSnackBar.show(context, 'Rendez-vous créé', kind: SnackKind.success);
      Navigator.pop(context);
    } else {
      // The server's refusal here is a slot conflict — it names the date/time
      // row, so it stays with the form rather than floating over it.
      setState(() => _selectionError = provider.error ?? 'Erreur');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // « Nouvelle » lives on the three controls that open this screen — the
      // journal FAB, its empty state, and the client sheet — so the bar names
      // the object rather than repeating the act (A15, §13.3).
      appBar: AppBar(title: const Text('Réservation')),
      body: Consumer2<ProAuthProvider, ProServiceProvider>(
        builder: (context, auth, serviceProvider, _) {
          final providerId = auth.activeSalonId;
          if (providerId == null || providerId.isEmpty) {
            return const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Profil incomplet',
              description:
                  'Configurez votre profil et vos services avant d’ajouter '
                  'un rendez-vous.',
            );
          }
          if (serviceProvider.isLoading && serviceProvider.services.isEmpty) {
            return const LoadingIndicator();
          }

          final services = serviceProvider.services;
          final total = services
              .where((s) => _selected.contains(s.id))
              .fold<double>(0, (sum, s) => sum + s.price);

          return ListView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            children: [
              _label('SERVICES'),
              if (services.isEmpty)
                Text(
                  'Ajoutez des services à votre profil pour pouvoir créer un '
                  'rendez-vous.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                )
              else
                ...services.map(
                  (s) => CheckboxListTile(
                    value: _selected.contains(s.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(s.id);
                      } else {
                        _selected.remove(s.id);
                      }
                    }),
                    title: Text(s.name),
                    subtitle: Text(
                      '${Formatters.formatPriceRange(s.price, s.priceMax, currency: context.read<ProAuthProvider>().salonCurrency)} · '
                      '${Formatters.formatDuration(s.durationMinutes)}',
                    ),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                ),
              const SizedBox(height: AppTheme.spacingM),
              _label('DATE & HEURE'),
              Row(
                children: [
                  Expanded(
                    child: _PickerField(
                      icon: Icons.calendar_today,
                      label: _date == null
                          ? 'Date'
                          : Formatters.formatDateShort(_date!),
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingM),
                  Expanded(
                    child: _PickerField(
                      icon: Icons.access_time,
                      label: _time == null ? 'Heure' : _time!.format(context),
                      onTap: _pickTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingM),
              _label('CLIENT'),
              AppTextField(
                label: 'Téléphone du client',
                hint: '+225 …',
                controller: _phone,
                focusNode: _phoneFocus,
                keyboardType: TextInputType.phone,
                enabled: !_anonymous,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                errorText: _errors['phone'],
                onChanged: (v) =>
                    setState(() => _errors.revalidate('phone', v)),
              ),
              CheckboxListTile(
                value: _anonymous,
                onChanged: (v) => setState(() => _anonymous = v ?? false),
                title: const Text('Client sans numéro (walk-in)'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
              const SizedBox(height: AppTheme.spacingS),
              AppTextField(
                label: 'Nom du client (optionnel)',
                controller: _name,
              ),
              const SizedBox(height: AppTheme.spacingS),
              SwitchListTile(
                value: _sendSms && !_anonymous && _phone.text.trim().isNotEmpty,
                onChanged: (_anonymous || _phone.text.trim().isEmpty)
                    ? null
                    : (v) => setState(() => _sendSms = v),
                title: const Text('Envoyer la confirmation par SMS'),
                subtitle: const Text(
                  'Le client reçoit un lien vers l’app (bientôt disponible)',
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: AppTheme.spacingS),
              AppTextField(
                label: 'Note (optionnel)',
                controller: _note,
                maxLines: 2,
              ),
              const SizedBox(height: AppTheme.spacingM),
              LabelValueRow(
                label: 'Total',
                value: Formatters.formatCurrency(
                  total,
                  currency: context.read<ProAuthProvider>().salonCurrency,
                ),
                labelStyle: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                valueStyle: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppTheme.spacingL),
              InlineFeedback(_selectionError),
              AppButton(
                text: 'Créer le rendez-vous',
                isLoading: _submitting,
                onPressed: _canSubmit ? () => _submit(total) : null,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
    child: Text(
      text,
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.textTertiary,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _PickerField extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickerField({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingSM,
          vertical: AppTheme.spacingM,
        ),
        decoration: BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: AppColors.borderStrong),
        ),
        child: Row(
          children: [
            Icon(icon, size: AppTheme.iconS, color: AppColors.textSecondary),
            const SizedBox(width: AppTheme.spacingS),
            // A14e closes A14b's open question, which was recorded honestly as
            // « Not measured — an open question, not a claim ». The `Text` was
            // UNFLEXED in a `Row` inside an `Expanded` half-width slot, so it
            // could only overflow, never wrap: an icon that does not text-scale
            // beside a label that goes from « Date » (4 chars) to « 15/01/2026 »
            // (10) the moment a date is chosen. `Expanded` lets it take the
            // room it needs and wrap — §13.3's answer everywhere else.
            Expanded(child: Text(label, style: AppTextStyles.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
