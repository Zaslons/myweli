import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/app_notification.dart';
import '../../providers/notifications_provider.dart';
import '../common/brand_refresh.dart';
import '../common/empty_state.dart';
import '../common/loading_indicator.dart';
import 'notification_tile.dart';

/// The notification feed — the SHARED body of both notification centres (the
/// consumer's `/notifications` and the pro's `/pro/notifications`). Each app
/// keeps its own chrome (bottom nav vs pro app bar); the list, its four
/// states, and the tap behaviour live here once.
///
/// A tap marks the row read and follows its `route` — which, for a salon
/// notification, carries `?salon=` so the pro app opens the booking under the
/// right salon (backend `SalonNotifier`; the pro appointment screen switches).
class NotificationsList extends StatefulWidget {
  const NotificationsList({
    super.key,
    this.emptyTitle = 'Aucune notification',
    this.emptyDescription =
        'Vos confirmations de rendez-vous et nouveautés apparaîtront ici.',
    this.onOpenRoute,
  });

  /// Empty-state copy (the pro app describes ITS events).
  final String emptyTitle;
  final String emptyDescription;

  /// Test seam: where a tapped row navigates (default: `context.push`).
  final void Function(BuildContext context, String route)? onOpenRoute;

  @override
  State<NotificationsList> createState() => _NotificationsListState();
}

class _NotificationsListState extends State<NotificationsList> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationsProvider>().load();
    });
  }

  void _open(NotificationsProvider provider, AppNotification n) {
    provider.markRead(n.id);
    final route = n.route;
    if (route == null || route.isEmpty) return;
    final open = widget.onOpenRoute;
    if (open != null) {
      open(context, route);
    } else {
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationsProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.notifications.isEmpty) {
          return const LoadingIndicator();
        }
        if (provider.loadFailed) {
          return EmptyState(
            icon: Icons.wifi_off,
            title: 'Chargement impossible',
            description: 'Vérifiez votre connexion et réessayez.',
            actionText: 'Réessayer',
            onAction: provider.load,
          );
        }
        if (provider.notifications.isEmpty) {
          return EmptyState(
            icon: Icons.notifications_none,
            title: widget.emptyTitle,
            description: widget.emptyDescription,
          );
        }
        return BrandRefresh(
          onRefresh: provider.load,
          child: ListView.separated(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            itemCount: provider.notifications.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppTheme.spacingM),
            itemBuilder: (context, index) {
              final n = provider.notifications[index];
              return NotificationTile(
                notification: n,
                onTap: () => _open(provider, n),
              );
            },
          ),
        );
      },
    );
  }
}
