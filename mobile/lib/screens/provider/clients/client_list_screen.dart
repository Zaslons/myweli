import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/salon_client.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_clients_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/brand_refresh.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';
import '../../../widgets/common/phone_number_field.dart';

/// The salon client base — « Clients » (module `clients` C1c,
/// docs/design/clients-c1.md §5). Derived from bookings: search, tag chips,
/// infinite scroll, manual add with phone dedupe (409 → opens the existing
/// card). Every read is audited server-side.
class ClientListScreen extends StatefulWidget {
  const ClientListScreen({super.key});

  @override
  State<ClientListScreen> createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  String get _providerId {
    final auth = context.read<ProAuthProvider>();
    return auth.activeSalonId ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProClientsProvider>().load(_providerId);
    });
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 200) {
        context.read<ProClientsProvider>().loadMore(_providerId);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        context.read<ProClientsProvider>().search(_providerId, value);
      }
    });
  }

  Future<void> _openAddSheet() async {
    final clients = context.read<ProClientsProvider>();
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddClientSheet(
        onSubmit: (name, phone, note) => clients.addClient(_providerId,
            name: name, phone: phone, note: note),
      ),
    );
    if (id == null || !mounted) return;
    if (clients.lastAddWasDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce numéro existe déjà.')),
      );
    }
    unawaited(context.push('/pro/clients/$id'));
  }

  @override
  Widget build(BuildContext context) {
    final clients = context.watch<ProClientsProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Clients')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.person_add),
        label: const Text('Ajouter un client'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingM,
              AppTheme.spacingM,
              AppTheme.spacingM,
              0,
            ),
            child: AppTextField(
              controller: _searchController,
              hint: 'Nom ou téléphone…',
              prefixIcon: const Icon(Icons.search),
              onChanged: _onSearchChanged,
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingM,
                vertical: AppTheme.spacingS,
              ),
              children: [
                for (final t in clients.availableTags)
                  Padding(
                    padding: const EdgeInsets.only(right: AppTheme.spacingS),
                    child: FilterChip(
                      label: Text(t),
                      selected: clients.tag == t,
                      onSelected: (_) => context
                          .read<ProClientsProvider>()
                          .filterByTag(_providerId, t),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _body(clients)),
        ],
      ),
    );
  }

  Widget _body(ProClientsProvider clients) {
    if (clients.isLoading) {
      return const LoadingIndicator();
    }
    if (clients.error != null) {
      return EmptyState(
        icon: Icons.wifi_off,
        title: 'Une erreur est survenue',
        description: clients.error,
        actionText: 'Réessayer',
        onAction: () => clients.load(_providerId),
      );
    }
    if (clients.isBaseEmpty) {
      return EmptyState(
        icon: Icons.people_outline,
        title: 'Vos clients apparaîtront ici',
        description:
            'Automatiquement, après leur première réservation. Vous pouvez '
            'aussi les ajouter vous-même.',
        actionText: '+ Ajouter un client',
        onAction: _openAddSheet,
      );
    }
    if (clients.clients.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'Aucun client trouvé',
        description: 'Essayez un autre nom ou numéro.',
      );
    }
    return BrandRefresh(
      onRefresh: () => clients.load(_providerId),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spacingM,
          0,
          AppTheme.spacingM,
          96, // clear the FAB
        ),
        itemCount: clients.clients.length + (clients.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i >= clients.clients.length) {
            return const Padding(
              padding: EdgeInsets.all(AppTheme.spacingM),
              child: LoadingIndicator(size: 24),
            );
          }
          return _ClientRow(client: clients.clients[i]);
        },
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client});

  final SalonClient client;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (client.phone != null) maskClientPhone(client.phone),
      if (client.visits > 0)
        '${client.visits} visite${client.visits > 1 ? 's' : ''}',
      if (client.lastVisitAt != null)
        'dernière ${Formatters.formatRelative(client.lastVisitAt!)}',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => context.push('/pro/clients/${client.id}'),
      leading: CircleAvatar(
        backgroundColor: AppColors.surfaceVariant,
        child: Text(
          client.displayName.isEmpty
              ? '?'
              : client.displayName[0].toUpperCase(),
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              client.displayName,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (client.linked) ...[
            const SizedBox(width: AppTheme.spacingXS),
            _MiniBadge(label: 'MyWeli', color: AppColors.textTertiary),
          ],
          if (client.noShows >= 1) ...[
            const SizedBox(width: AppTheme.spacingXS),
            _MiniBadge(
              label: client.noShows == 1
                  ? '1 absence'
                  : '${client.noShows} absences',
              color: client.noShows >= 2
                  ? AppColors.error
                  : AppColors.textSecondary,
            ),
          ],
        ],
      ),
      subtitle: Text(
        subtitleParts.join(' · '),
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      trailing: client.tags.isEmpty
          ? null
          : Wrap(
              spacing: AppTheme.spacingXS,
              children: [
                for (final t in client.tags.take(2))
                  _MiniBadge(label: t, color: AppColors.textSecondary),
              ],
            ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingS, vertical: AppTheme.spacingXS),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}

class _AddClientSheet extends StatefulWidget {
  const _AddClientSheet({required this.onSubmit});

  final Future<String?> Function(String name, String phone, String? note)
      onSubmit;

  @override
  State<_AddClientSheet> createState() => _AddClientSheetState();
}

class _AddClientSheetState extends State<_AddClientSheet> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  String _phone = '';
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final id = await widget.onSubmit(
      _nameController.text.trim(),
      _phone,
      _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (id != null) {
      Navigator.of(context).pop(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = context.watch<ProClientsProvider>().error;
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
            'Ajouter un client',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          AppTextField(
            controller: _nameController,
            label: 'Nom',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppTheme.spacingM),
          PhoneNumberField(onChanged: (e164) => _phone = e164),
          const SizedBox(height: AppTheme.spacingM),
          AppTextField(
            controller: _noteController,
            label: 'Note (optionnelle)',
            hint: 'Ex : Préfère Awa',
            maxLength: 500,
          ),
          if (error != null) ...[
            const SizedBox(height: AppTheme.spacingS),
            Text(
              error,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: AppTheme.spacingM),
          AppButton(
            text: 'Ajouter',
            isLoading: _busy,
            onPressed: (_busy ||
                    _nameController.text.trim().isEmpty ||
                    _phone.trim().isEmpty)
                ? null
                : _submit,
          ),
        ],
      ),
    );
  }
}
