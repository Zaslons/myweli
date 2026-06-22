import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../providers/pro_appointment_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_service_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';

class ProManualBookingScreen extends StatefulWidget {
  const ProManualBookingScreen({super.key});

  @override
  State<ProManualBookingScreen> createState() => _ProManualBookingScreenState();
}

class _ProManualBookingScreenState extends State<ProManualBookingScreen> {
  final Set<String> _selected = {};
  DateTime? _date;
  TimeOfDay? _time;
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _note = TextEditingController();
  bool _anonymous = false;
  bool _sendSms = true;
  bool _submitting = false;
  String? _providerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = context.read<ProAuthProvider>().provider?.providerId;
      if (id != null && id.isNotEmpty) {
        _providerId = id;
        context.read<ProServiceProvider>().loadServices(id);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime? get _dateTime {
    if (_date == null || _time == null) return null;
    return DateTime(
        _date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);
  }

  bool get _canSubmit =>
      _selected.isNotEmpty &&
      _dateTime != null &&
      (_anonymous || _phone.text.trim().isNotEmpty) &&
      !_submitting;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
        context: context, initialTime: _time ?? TimeOfDay.now());
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit(double total) async {
    final dt = _dateTime;
    if (dt == null) return;
    if (dt.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Choisissez une date et une heure à venir')),
      );
      return;
    }

    setState(() => _submitting = true);
    final provider = context.read<ProAppointmentProvider>();
    final ok = await provider.createManualBooking(
      providerId: _providerId!,
      serviceIds: _selected.toList(),
      appointmentDateTime: dt,
      clientName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      clientPhone: _anonymous ? null : _phone.text.trim(),
      notes: _note.text.trim().isEmpty ? null : _note.text.trim(),
      sendSmsInvite: _sendSms && !_anonymous && _phone.text.trim().isNotEmpty,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rendez-vous créé'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Erreur'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Nouveau rendez-vous')),
      body: Consumer2<ProAuthProvider, ProServiceProvider>(
        builder: (context, auth, serviceProvider, _) {
          final providerId = auth.provider?.providerId;
          if (providerId == null || providerId.isEmpty) {
            return const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Profil incomplet',
              description:
                  'Configurez votre profil et vos services avant d\'ajouter '
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
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textTertiary),
                )
              else
                ...services.map((s) => CheckboxListTile(
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
                        '${Formatters.formatPriceRange(s.price, s.priceMax)} · '
                        '${Formatters.formatDuration(s.durationMinutes)}',
                      ),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    )),
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
                hint: '+225 ...',
                controller: _phone,
                keyboardType: TextInputType.phone,
                enabled: !_anonymous,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
              ),
              CheckboxListTile(
                value: _anonymous,
                onChanged: (v) => setState(() => _anonymous = v ?? false),
                title: const Text('Client sans numéro (walk-in)'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
              const SizedBox(height: 8),
              AppTextField(
                label: 'Nom du client (optionnel)',
                controller: _name,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _sendSms && !_anonymous && _phone.text.trim().isNotEmpty,
                onChanged: (_anonymous || _phone.text.trim().isEmpty)
                    ? null
                    : (v) => setState(() => _sendSms = v),
                title: const Text('Envoyer la confirmation par SMS'),
                subtitle: const Text(
                    'Le client reçoit un lien vers l\'app (bientôt disponible)'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 8),
              AppTextField(
                label: 'Note (optionnel)',
                controller: _note,
                maxLines: 2,
              ),
              const SizedBox(height: AppTheme.spacingM),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary)),
                  Text(
                    Formatters.formatCurrency(total),
                    style: AppTextStyles.titleMedium
                        .copyWith(color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingL),
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
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: AppTextStyles.labelSmall
              .copyWith(color: AppColors.textTertiary, letterSpacing: 0.5),
        ),
      );
}

class _PickerField extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickerField(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(label, style: AppTextStyles.bodyMedium),
          ],
        ),
      ),
    );
  }
}
