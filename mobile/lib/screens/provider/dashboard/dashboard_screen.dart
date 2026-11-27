import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:provider/provider.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/salon_go_live.dart';
import '../../../core/utils/salon_id.dart';
import '../../../models/pro_membership.dart';
import '../../../models/revenue_analytics.dart';
import '../../../providers/notifications_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_dashboard_provider.dart';
import '../../../providers/pro_team_provider.dart';
import '../../../services/interfaces/pro_service_interface.dart';
import '../../../widgets/common/app_async_view.dart';
import '../../../widgets/common/app_card.dart';
import '../../../widgets/common/app_skeleton.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/screen_title.dart';
import '../../../widgets/common/update_nudge_slot.dart';
import '../../../widgets/pro/revenue/kpi_grid.dart';
import '../../../widgets/provider/salon_picker_sheet.dart';
import '../../../widgets/push/push_permission_sheet.dart';
import '../../../widgets/team/pro_invitations_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// The pull (owner decision 9): it always asks the server. With figures on
  /// screen they stay when it fails, and the reason is said once.
  Future<void> _pull(ProDashboardProvider dashboard) async {
    final authProvider = context.read<ProAuthProvider>();
    if (authProvider.provider == null) return;
    // The invitations card reads its list again too (B7.6), beside the
    // figures — its failure stays silent, as on mount.
    unawaited(context.read<ProTeamProvider>().loadMyInvitations());
    await dashboard.refresh(_resolvedProviderId(context));
    if (!mounted) return;
    final failure = dashboard.takeRefreshFailure();
    if (failure != null) {
      AppSnackBar.show(context, failure, kind: SnackKind.error);
    }
  }

  SalonId _resolvedProviderId(BuildContext context) {
    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    return authProvider.activeSalonId ?? SalonId.none;
  }

  /// R6: the salon the stats were loaded for — a « Mes salons » switch
  /// happens WITHOUT remounting this screen, so a change triggers a reload.
  SalonId? _loadedForSalon;

  /// Open the switcher, and the post-switch reshape
  /// (a staff membership in the new salon lands on the staff shell).
  Future<void> _openSalonPicker() async {
    final result = await showSalonPicker(context);
    if (!mounted || result == null) return;
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
        final dashboardProvider = Provider.of<ProDashboardProvider>(
          context,
          listen: false,
        );
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
  ///
  /// The sentence names the four events the server sends a salon
  /// (`SalonEvent`: new booking, client reschedule, client cancellation,
  /// deposit proof) — and no other (promise-honesty-sweep.md T3;
  /// salon-client-reschedule-notify.md N3). « Reporte » is the client's own
  /// word (« Reporter »): a client can only move the time.
  Future<void> _maybeAskPush() async {
    if (!mounted) return;
    await serviceLocator.proPushRegistration.maybePromptOnce(
      () => showPushPermissionSheet(
        context,
        body:
            'Soyez prévenu·e dès qu’un client réserve, reporte, annule ou '
            'envoie son acompte, et ne manquez aucune demande.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        // **« Tableau de bord » is 231.1dp and this bar's budget is 232.**
        // It cleared by 0.9dp, so the corpus run and the matrix both read it
        // green — and the device at `accessibility-large` still rendered
        // « Tableau de b… », which is the string §21 row 79 was opened with.
        // A margin under a device pixel is not a pass.
        //
        // Neither action can give: the bell and the profile are both already
        // icons, and `/pro/profile` is reachable from **nowhere else** in the
        // app, so removing it would strand the screen. So the title gives, to
        // the word the house already uses for a landing screen (§17.1 — the
        // consumer bottom nav says « Accueil » in five places).
        title: const ScreenTitle('Accueil'),
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
                context.read<ProDashboardProvider>().loadDashboardStats(
                  salonId,
                );
              }
            });
          }
          if (!authProvider.isAuthenticated) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: AppTheme.iconXL,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  Text(
                    'Veuillez vous connecter',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
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

          // The house error state, inside the pull — never a dead end, and
          // never the failure's own text
          // (docs/design/app-pro-home-journal-fresh.md §2.3, §9); since B9.8
          // the shared one.
          return AppAsyncView<DashboardStats>(
            isLoading: dashboardProvider.isLoading,
            error: dashboardProvider.error == null
                ? null
                : dashboardProvider.errorIsOffline
                ? ProDashboardProvider.noConnection
                : ProDashboardProvider.failedRetry,
            // A full load is a salon switch's: the stats on hand are the last
            // salon's. A pull is quiet and keeps them (`_pull`). Null with no
            // error is « not asked yet » — the first frame, or right after a
            // switch: the load starts after this frame.
            data: dashboardProvider.isLoading ? null : dashboardProvider.stats,
            isEmpty: (_) => false,
            loading: const SkeletonDetail(sections: 3),
            empty: const SizedBox.shrink(),
            onRetry: () => dashboardProvider.loadDashboardStats(
              _resolvedProviderId(context),
            ),
            onRefresh: () => _pull(dashboardProvider),
            builder: (context, stats) =>
                _home(authProvider, dashboardProvider, stats),
          );
        },
      ),
    );
  }

  Widget _home(
    ProAuthProvider authProvider,
    ProDashboardProvider dashboardProvider,
    DashboardStats stats,
  ) {
    return BrandRefresh(
      onRefresh: () => _pull(dashboardProvider),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Advice about the app itself, above the salon's own content.
            // Renders nothing in the normal case.
            const UpdateNudgeSlot(),
            // R6: the header IS the salon switcher (chevron when the
            // account has several salons; « Mes salons » lives on the
            // Profil screen too).
            InkWell(
              onTap: authProvider.hasMultipleSalons ? _openSalonPicker : null,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      // No name, no vocative: « Bienvenue, votre
                      // salon » is not French.
                      authProvider.knownSalonName == null
                          ? 'Bienvenue'
                          : 'Bienvenue, ${authProvider.knownSalonName}',
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (authProvider.hasMultipleSalons) ...[
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
            // The account's own invitations, under the salon they are
            // read in and above its content — nothing at all when there
            // is none (pro-app-batch7.md §2.6, B7.6).
            const ProInvitationsCard(),
            // Go-live is owner-only (salon.publish, sign-off) — the
            // card hides for members; the server 403s regardless.
            // Its subtitle follows where the salon stands with MyWeli's
            // validation (B0.18, decision 136 item 1); not read yet (an
            // offline cold start) it keeps today's words.
            if (authProvider.can(ProCap.salonPublish)) ...[
              AppCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.checklist_rounded),
                  title: const Text('Configurer mon profil'),
                  subtitle: Text(
                    homeCardSubtitle(authProvider.salonGoLiveState),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pro/onboarding'),
                ),
              ),
              const SizedBox(height: AppTheme.spacingS),
            ],
            const SizedBox(height: AppTheme.spacingM),
            // Stats cards — two across, or all of them one per row
            // when a value would not fit a half-width card.
            // Money figures are field-gated server-side without
            // finances.view (R1/R4) — absence is a valid state, and
            // then the two counts decide alone.
            //
            // « Revenus prévus », not « Revenus »: these count
            // confirmed + completed bookings, while the « Revenus »
            // screen (« Analyses ») counts completed only — one word
            // over two numbers for the same day
            // (provider-dashboard-stats.md §12).
            //
            // The two money cards open « Revenus » on their own period
            // (pro-revenue-analytics.md §4.1, Q2) — for `finances.view`
            // only; the server answers 403 to anyone else regardless.
            KpiGrid(
              tiles: [
                KpiTile(
                  title: 'Aujourd’hui',
                  value: stats.todayAppointments.toString(),
                  caption: 'Rendez-vous',
                  icon: Icons.calendar_today,
                  iconColor: AppColors.primary,
                ),
                KpiTile(
                  title: 'En attente',
                  value: stats.pendingRequests.toString(),
                  caption: 'Demandes',
                  icon: Icons.pending,
                  iconColor: AppColors.warning,
                ),
                if (stats.hasRevenue) ...[
                  KpiTile(
                    title: 'Aujourd’hui',
                    value: Formatters.formatCurrency(
                      stats.todayRevenue!,
                      currency: context.read<ProAuthProvider>().salonCurrency,
                    ),
                    caption: 'Revenus prévus',
                    icon: Icons.attach_money,
                    iconColor: AppColors.success,
                    onTap: authProvider.can(ProCap.financesView)
                        ? () => _openRevenue(context, RevenuePeriod.day)
                        : null,
                  ),
                  KpiTile(
                    title: 'Ce mois',
                    value: Formatters.formatCurrency(
                      stats.monthRevenue!,
                      currency: context.read<ProAuthProvider>().salonCurrency,
                    ),
                    caption: 'Revenus prévus',
                    icon: Icons.trending_up,
                    iconColor: AppColors.info,
                    onTap: authProvider.can(ProCap.financesView)
                        ? () => _openRevenue(context, RevenuePeriod.month)
                        : null,
                  ),
                ],
              ],
            ),
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
  }
}

/// « Revenus » on [period], today (no date: the server's today, §3.5).
void _openRevenue(BuildContext context, RevenuePeriod period) {
  context.push(
    Uri(
      path: '/pro/earnings',
      queryParameters: {'period': period.name},
    ).toString(),
  );
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
              child: i + 1 < cards.length
                  ? cards[i + 1]
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
  return rows;
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
    return ConstrainedBox(
      // `constraints`, not `height:` — see [_minHeight]: the card grows past it.
      constraints: const BoxConstraints(minHeight: _minHeight),
      child: AppCard(
        onTap: onTap,
        child: Column(
          children: [
            Icon(icon, size: AppTheme.iconL, color: AppColors.primary),
            const SizedBox(height: AppTheme.spacingS),
            Text(
              title,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
