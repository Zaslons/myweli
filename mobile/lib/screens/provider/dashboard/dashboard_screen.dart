import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/pro_membership.dart';
import '../../../providers/notifications_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_dashboard_provider.dart';
import '../../../widgets/provider/salon_picker_sheet.dart';
import '../../../widgets/push/push_permission_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _resolvedProviderId(BuildContext context) {
    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    return authProvider.activeSalonId ?? '';
  }

  /// R6: the salon the stats were loaded for — a « Mes salons » switch
  /// happens WITHOUT remounting this screen, so a change triggers a reload.
  String? _loadedForSalon;

  /// Open the switcher; handle the add flow and the post-switch reshape
  /// (a staff membership in the new salon lands on the staff shell).
  Future<void> _openSalonPicker() async {
    final result = await showSalonPicker(context);
    if (!mounted || result == null) return;
    if (result == 'add') {
      unawaited(context.push('/pro/salons/nouveau'));
      return;
    }
    final auth = context.read<ProAuthProvider>();
    if (auth.isStaff) {
      context.go('/pro/staff');
    }
    // Same shell: the Consumer below sees the new activeSalonId and reloads.
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.provider != null) {
        final dashboardProvider =
            Provider.of<ProDashboardProvider>(context, listen: false);
        _loadedForSalon = _resolvedProviderId(context);
        dashboardProvider.loadDashboardStats(_loadedForSalon!);
        // The bell's unread badge (the salon's notification feed).
        unawaited(context.read<NotificationsProvider>().load());
        _maybeAskPush();
      }
    });
  }

  /// On the first dashboard visit, offer to enable push (once). Best-effort —
  /// pros want new-booking alerts immediately, so we ask here rather than later.
  Future<void> _maybeAskPush() async {
    if (!mounted) return;
    await serviceLocator.proPushRegistration.maybePromptOnce(
      () => showPushPermissionSheet(
        context,
        body: 'Soyez prévenu·e dès qu’un client réserve, annule ou modifie '
            'un rendez-vous, et ne manquez aucune demande.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Tableau de bord'),
        actions: [
          Consumer<NotificationsProvider>(
            builder: (context, notifications, _) {
              final unread = notifications.unreadCount;
              final bell = IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Notifications',
                onPressed: () => context.push('/pro/notifications'),
              );
              if (unread == 0) return bell;
              return Badge.count(
                count: unread,
                backgroundColor: AppColors.error,
                textColor: AppColors.secondary,
                offset: const Offset(-6, 6),
                child: bell,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_circle),
            tooltip: 'Profil',
            onPressed: () => context.push('/pro/profile'),
          ),
        ],
      ),
      body: Consumer2<ProAuthProvider, ProDashboardProvider>(
        builder: (context, authProvider, dashboardProvider, _) {
          // R6: a salon switch re-scopes the dashboard in place.
          final salonId = authProvider.activeSalonId;
          if (salonId != null &&
              _loadedForSalon != null &&
              salonId != _loadedForSalon) {
            _loadedForSalon = salonId;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                context
                    .read<ProDashboardProvider>()
                    .loadDashboardStats(salonId);
              }
            });
          }
          if (!authProvider.isAuthenticated) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline,
                      size: AppTheme.iconXL, color: AppColors.textSecondary),
                  const SizedBox(height: AppTheme.spacingM),
                  Text(
                    'Veuillez vous connecter',
                    style: AppTextStyles.titleLarge
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  ElevatedButton(
                    onPressed: () => context.go('/pro/login'),
                    child: const Text('Se connecter'),
                  ),
                ],
              ),
            );
          }

          if (dashboardProvider.isLoading) {
            return const Center(child: LoadingIndicator());
          }

          final stats = dashboardProvider.stats;
          if (stats == null) {
            return Center(
              child: Text(
                dashboardProvider.error ?? 'Aucune donnée disponible',
                style: AppTextStyles.bodyLarge
                    .copyWith(color: AppColors.textSecondary),
              ),
            );
          }

          return BrandRefresh(
            onRefresh: () async {
              if (authProvider.provider != null) {
                await dashboardProvider
                    .loadDashboardStats(_resolvedProviderId(context));
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppTheme.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // R6: the header IS the salon switcher (chevron when the
                  // account has several salons; « Mes salons » lives on the
                  // Profil screen too).
                  InkWell(
                    onTap: authProvider.hasMultipleSalons ||
                            authProvider.canAddSalon
                        ? _openSalonPicker
                        : null,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Bienvenue, ${authProvider.salonName}',
                            style: AppTextStyles.headlineMedium
                                .copyWith(color: AppColors.textPrimary),
                          ),
                        ),
                        if (authProvider.hasMultipleSalons ||
                            authProvider.canAddSalon) ...[
                          const SizedBox(width: AppTheme.spacingXS),
                          const Icon(
                            Icons.expand_more,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  // Go-live is owner-only (salon.publish, sign-off) — the
                  // card hides for members; the server 403s regardless.
                  if (authProvider.can(ProCap.salonPublish)) ...[
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.checklist_rounded),
                        title: const Text('Configurer mon profil'),
                        subtitle: const Text(
                            'Complétez les étapes pour aller en ligne'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/pro/onboarding'),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingS),
                  ],
                  const SizedBox(height: AppTheme.spacingM),
                  // Stats Cards
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Aujourd’hui',
                          value: stats.todayAppointments.toString(),
                          subtitle: 'Rendez-vous',
                          icon: Icons.calendar_today,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingSM),
                      Expanded(
                        child: _StatCard(
                          title: 'En attente',
                          value: stats.pendingRequests.toString(),
                          subtitle: 'Demandes',
                          icon: Icons.pending,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                  // Money figures are field-gated server-side without
                  // finances.view (R1/R4) — absence is a valid state.
                  if (stats.hasRevenue) ...[
                    const SizedBox(height: AppTheme.spacingSM),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            title: 'Aujourd’hui',
                            value: Formatters.formatCurrency(
                              stats.todayRevenue!,
                              currency:
                                  context.read<ProAuthProvider>().salonCurrency,
                            ),
                            subtitle: 'Revenus',
                            icon: Icons.attach_money,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingSM),
                        Expanded(
                          child: _StatCard(
                            title: 'Ce mois',
                            value: Formatters.formatCurrency(
                              stats.monthRevenue!,
                              currency:
                                  context.read<ProAuthProvider>().salonCurrency,
                            ),
                            subtitle: 'Revenus',
                            icon: Icons.trending_up,
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppTheme.spacingL),
                  // Role-gated sections (access R4b): UI hiding is
                  // convenience — the routes 403 server-side regardless.
                  ..._section(context, 'Opérations quotidiennes', [
                    if (authProvider.can(ProCap.journalViewAll))
                      _ActionCard(
                        title: 'Rendez-vous',
                        icon: Icons.calendar_today,
                        onTap: () => context.push('/pro/journal'),
                      ),
                    if (authProvider.can(ProCap.clientsView))
                      _ActionCard(
                        title: 'Clients',
                        icon: Icons.people,
                        onTap: () => context.push('/pro/clients'),
                      ),
                    if (authProvider.can(ProCap.availabilityManage))
                      _ActionCard(
                        title: 'Disponibilité',
                        icon: Icons.access_time,
                        onTap: () => context.push('/pro/availability'),
                      ),
                  ]),
                  ..._section(context, 'Configuration', [
                    if (authProvider.can(ProCap.catalogueManage)) ...[
                      _ActionCard(
                        title: 'Services',
                        icon: Icons.build,
                        onTap: () => context.push('/pro/services'),
                      ),
                      _ActionCard(
                        title: 'Employés',
                        icon: Icons.people,
                        onTap: () => context.push('/pro/artists'),
                      ),
                    ],
                  ]),
                  ..._section(context, 'Analyses', [
                    if (authProvider.can(ProCap.financesView))
                      _ActionCard(
                        title: 'Revenus',
                        icon: Icons.attach_money,
                        onTap: () => context.push('/pro/earnings'),
                      ),
                    if (authProvider.can(ProCap.profileManage))
                      _ActionCard(
                        title: 'Avis',
                        icon: Icons.star,
                        onTap: () => context.push('/pro/reviews'),
                      ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A titled action grid, omitted entirely when the role leaves it empty.
List<Widget> _section(BuildContext context, String title, List<Widget> cards) {
  if (cards.isEmpty) return const [];
  return [
    Text(
      title,
      style: AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimary),
    ),
    const SizedBox(height: AppTheme.spacingSM),
    // A12: this was `GridView.count(childAspectRatio: 1.1)`, and an aspect ratio
    // freezes tile HEIGHT as a multiple of tile WIDTH — which does not move with
    // the OS text scale. The tile was **143.6dp at 100% and 143.6dp at 200%,
    // forever**: « Rendez-vous » wraps to two lines and runs past the bottom,
    // and « Disponibilité » is one unbreakable word that is simply clipped —
    // no overflow, no exception, nothing for a gate to catch (§21 row 68).
    //
    // The fix is not a computed extent. `AppTheme.textScaledBound` is right when
    // a scroller DEMANDS a bound (`ProviderCard.carouselHeight`); here nothing
    // does, so the honest answer is to stop naming a height at all. Two
    // `Expanded`s under an `IntrinsicHeight` give the same two-column grid with
    // tiles that are equal to each other and as tall as their own content —
    // §5's rule, applied vertically: divide the row, do not dimension the boxes.
    //
    // The gaps were raw `12`s, invisible to the §5 pin because its `\b` cannot
    // fire inside `crossAxisSpacing`. They are `spacingSM` now, which is what
    // 12 already meant.
    ..._actionRows(context, cards),
    const SizedBox(height: AppTheme.spacingL),
  ];
}

/// Above this OS text scale the grid becomes a single column.
///
/// **Measured, not chosen** — and the picture is what found it. Two columns
/// give a tile 126dp of inner width; « Disponibilité » is thirteen characters
/// with no space in them, so at `bodyMedium` it needs ~100dp at 1× and passes
/// 126 just after **1.26×**. Past that it does not wrap, it BREAKS — the golden
/// at 360×2× read « Disponibil / ité » — and §13.3 is explicit that a control's
/// label may not break inside a word, because a button is read as one thing.
///
/// The same threshold and the same shape as the salon page's action bar
/// (`provider_detail_screen.dart`), which stacks « Appeler » and « Réserver »
/// above 1.3× for exactly this reason: *"the fix is always more width, never a
/// smaller font — a one-word label cannot wrap its way out."* A text-scale
/// branch, not a §10 breakpoint: what changed is how much room a word needs,
/// not how much room the screen has.
const double _kActionGridSingleColumnAbove = 1.3;

/// [cards] laid out two per row — or one, past
/// [_kActionGridSingleColumnAbove] — each row as tall as its tallest card.
List<Widget> _actionRows(BuildContext context, List<Widget> cards) {
  final perRow =
      MediaQuery.textScalerOf(context).scale(1) > _kActionGridSingleColumnAbove
          ? 1
          : 2;
  if (perRow == 1) {
    final single = <Widget>[];
    for (var i = 0; i < cards.length; i++) {
      if (i > 0) single.add(const SizedBox(height: AppTheme.spacingSM));
      // `double.infinity`, or the card shrink-wraps: the dashboard body is a
      // `Column(crossAxisAlignment: start)`, so a bare child takes its INTRINSIC
      // width and a single-column grid renders as a stack of half-width cards
      // hugging the left edge. The golden showed exactly that before this line.
      single.add(SizedBox(width: double.infinity, child: cards[i]));
    }
    return single;
  }
  final rows = <Widget>[];
  for (var i = 0; i < cards.length; i += 2) {
    if (i > 0) rows.add(const SizedBox(height: AppTheme.spacingSM));
    rows.add(
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: cards[i]),
            const SizedBox(width: AppTheme.spacingSM),
            // An empty second slot rather than a centred single card: the odd
            // card keeps its column, so the grid stays a grid.
            Expanded(
              child:
                  i + 1 < cards.length ? cards[i + 1] : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
  return rows;
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        boxShadow: AppTheme.elevation1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A12 — §21 row 68's finding #3, and the mechanism is worth naming:
          // **an icon does not text-scale.** The theme sets no
          // `applyTextScaling`, so this glyph is 20dp at every scale while
          // « Aujourd'hui » doubles from 60 to 121 — in a tile whose inner
          // width is 126. Measured at 360×2×: **19px over**, and 6.1px for
          // « En attente ». Device-confirmed first, at 16px / 2.6px on a
          // 360×780pt iPhone at ≈1.95×.
          //
          // A `Wrap`, for the third time in this codebase
          // (`section_heading.dart`, `review_tile.dart`): the icon drops to its
          // own line rather than squeezing a title that cannot help it.
          // « Aujourd'hui » is ONE WORD — it cannot wrap its way out, so
          // `Flexible` here would only trade an overflow for a crush, and the
          // legibility gate would take the second one.
          //
          // `double.infinity` is load-bearing, as it is at both precedents: a
          // Wrap shrink-wraps, so `spaceBetween` inside one has nothing to
          // distribute and the icon would sit against the title.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: AppTheme.spacingXS,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
                Icon(icon, color: color, size: AppTheme.iconS),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            value,
            style: AppTextStyles.headlineSmall
                .copyWith(color: AppColors.textPrimary),
          ),
          Text(
            subtitle,
            style:
                AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  /// The airy height the old `childAspectRatio: 1.1` produced at §10's 360dp
  /// floor — `(360 − 32 − 12) / 2 / 1.1`.
  ///
  /// A **minimum**, not a height, which is the difference §13.3 draws: the card
  /// keeps its designed proportion at 1× and grows past it when the label needs
  /// two lines. The ratio it replaces did the first and refused the second, and
  /// it also made the card taller on a wider phone — 157 at 390 — for no reason
  /// anyone chose. One number at every width is the simpler promise.
  static const double _minHeight = 143.6;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // `constraints`, not `height:` — see [_minHeight].
        constraints: const BoxConstraints(minHeight: _minHeight),
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(AppTheme.radiusXL),
          boxShadow: AppTheme.elevation1,
        ),
        child: Column(
          children: [
            Icon(icon, size: AppTheme.iconL, color: AppColors.primary),
            const SizedBox(height: AppTheme.spacingS),
            Text(
              title,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
