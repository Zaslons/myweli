import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/di/dependency_injection.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_indicator.dart';
import '../providers/provider_detail_screen.dart';

/// « Aperçu de ma page » — the owner sees their salon as a client will.
///
/// **Why this screen exists at all.** The preview renders the real consumer
/// screen, and that screen fetches through `ProviderProvider`, which reads the
/// **public, unauthenticated** `GET /providers/{id}`. So the pro app was asking
/// the anonymous door for the salon it was already signed into — and would have
/// 404'd its owner's own draft the day that route stops serving drafts
/// (T51; `docs/design/salon-state-and-refusals.md` Decision C). Three documents
/// already claimed this could not happen: T51's *« Pro-own surfaces resolve by
/// account and keep working »*, `pro-salon-lifecycle.md` §49-53, and its own B4
/// note about the web preview. Web obeyed them; mobile did not.
///
/// **The shape is web's, exactly.** `web/components/pro/SalonPreviewClient.tsx`
/// fetches `/me/provider` and passes the object into the shared `ProviderView`
/// as a prop — *« the real consumer page component fed from /me/provider
/// (owner-scoped), so drafts stay invisible to everyone else (T51) and no new
/// endpoint exists »*. Mobile's shared screen reads a `ChangeNotifier` rather
/// than a prop, so the notifier is what gets handed the payload
/// ([ProviderProvider.showPreloaded]). Same fetch, same authority, same
/// absence of a new endpoint.
///
/// **One difference from the public read, recorded rather than hidden.**
/// `/me/provider` does not embed the 10-review preview that `GET /providers/{id}`
/// adds, so `Provider.fromJson` yields `reviews: []` and the « Avis » section
/// renders empty here. Web ships with the identical limitation — its
/// `ProProfile` type has no `reviews` field — so this is parity, not a new
/// loss. A salon still unpublished has no reviews to show anyway; a live one
/// previewing its page will not see the ones it has.
class SalonPreviewScreen extends StatefulWidget {
  const SalonPreviewScreen({super.key});

  @override
  State<SalonPreviewScreen> createState() => _SalonPreviewScreenState();
}

class _SalonPreviewScreenState extends State<SalonPreviewScreen> {
  bool _loading = true;
  bool _failed = false;
  String _providerId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    // No `providerId` argument: `getMyProvider` resolves the acting salon from
    // the token, honouring the R6 persisted multi-salon selection on the way.
    // Passing an id would re-introduce the thing this screen exists to remove.
    final res = await serviceLocator.proService.getMyProvider();
    if (!mounted) return;
    final salon = res.data?.salon;
    if (salon == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    context.read<ProviderProvider>().showPreloaded(salon);
    setState(() {
      _loading = false;
      _providerId = salon.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: LoadingIndicator()));
    }
    if (_failed) {
      // §12's way out, and here a retry CAN succeed — the read is authenticated
      // and the usual cause is the network, not the salon's state.
      return Scaffold(
        appBar: AppBar(title: const Text('Aperçu')),
        body: EmptyState(
          icon: Icons.wifi_off,
          title: 'Chargement impossible',
          description: 'Vérifiez votre connexion et réessayez.',
          actionText: 'Réessayer',
          onAction: _load,
        ),
      );
    }
    return ProviderDetailScreen(providerId: _providerId, preview: true);
  }
}
