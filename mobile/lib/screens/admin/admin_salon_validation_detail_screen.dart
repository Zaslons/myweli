import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/salon_categories.dart';
import '../../core/constants/unnamed_salon.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/external_link.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/phone_numbering.dart';
import '../../core/utils/salon_id.dart';
import '../../core/utils/salon_time.dart';
import '../../core/utils/status_labels.dart';
import '../../core/utils/validation_labels.dart';
import '../../models/admin_salon_validation.dart';
import '../../models/salon_subscription.dart';
import '../../providers/admin/admin_salon_validation_detail_provider.dart';
import '../../services/admin/admin_service.dart';
import '../../widgets/common/app_async_view.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_skeleton.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/inline_feedback.dart';
import '../../widgets/common/label_value_row.dart';
import 'widgets/admin_scaffold.dart';
import 'widgets/refusal_dialog.dart';
import 'widgets/status_chip.dart';
import 'widgets/validation_unavailable.dart';

/// One salon's request to go public, and the decision (B0.18 —
/// docs/design/salon-go-live-approval.md §4.3, §4.4).
///
/// **Two columns, as the KYC detail** — stacked when the window (or the
/// text size) leaves too little room for two:
///
/// - **the salon**: name and type, the request's state, the offer, the
///   photos, the services and their prices, the hours, the address, the
///   country, **the pin's coordinates with « Ouvrir dans OpenStreetMap »**
///   and **the phone with its calling code** — decision 123's evidence that
///   the salon is in Côte d'Ivoire;
/// - **the owner**: name, contact, account age, KYC (« aucun document », or
///   « N documents · {status} » with its link), the other salons they own,
///   and the request's history.
///
/// **The sticky bar**: « Refuser » (destructive, a pending request only) and
/// « Valider la mise en ligne » — sent `from` the state this screen read:
/// `pending`, `refused` (validating from « Refusés »), or `approved` for a
/// validation that did not finish taking the salon live (« Validation à
/// terminer »). On a suspended salon it is disabled, and the bar says why in
/// words. A 409 is said in the bar, worded per code (`missing` named).
///
/// **The four states** are [AppAsyncView]'s, keyed to this screen's id (the
/// provider is app-wide: B9.8's stale-detail guard). A salon that does not
/// exist is a state of its own; a server from before B0.18 the calm notice.
class AdminSalonValidationDetailScreen extends StatefulWidget {
  const AdminSalonValidationDetailScreen({super.key, required this.id});

  final SalonId id;

  static const title = 'Demande de mise en ligne';

  /// The salon's pin on OpenStreetMap — a link needs no map key (the console
  /// is built without one, §4.3), and it still tells Dakar from Abidjan.
  static String openStreetMapUrl(double latitude, double longitude) {
    final lat = latitude.toStringAsFixed(6);
    final lng = longitude.toStringAsFixed(6);
    return 'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng';
  }

  @override
  State<AdminSalonValidationDetailScreen> createState() =>
      _AdminSalonValidationDetailScreenState();
}

class _AdminSalonValidationDetailScreenState
    extends State<AdminSalonValidationDetailScreen> {
  /// Below this content width (at the default text size, scaled with it),
  /// the owner's column would fall under ~270dp: the columns stack. A layout
  /// dimension, not a token (SYSTEM.md §5, « What §5 does not govern »).
  static const double _twoColumnsMinWidth = 720;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant AdminSalonValidationDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  void _load() =>
      context.read<AdminSalonValidationDetailProvider>().load(widget.id);

  Future<void> _approve() async {
    final p = context.read<AdminSalonValidationDetailProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await p.approve(widget.id);
    // A failure is the bar's to say (a 409's sentence, under the buttons);
    // the detail re-reads itself meanwhile.
    if (!mounted || !ok) return;
    AppSnackBar.showOn(
      messenger,
      'Salon validé : il est en ligne.',
      kind: SnackKind.success,
    );
    context.go('/admin/salon-validations');
  }

  /// The refusal dialog is open: what a submit answers is the dialog's to
  /// say (§14, §15), not the bar's behind the barrier.
  bool _refusing = false;

  Future<void> _refuse() async {
    final p = context.read<AdminSalonValidationDetailProvider>();
    final messenger = ScaffoldMessenger.of(context);
    p.clearActionError();
    setState(() => _refusing = true);
    final result = await showRefusalDialog(
      context,
      refuse: (code, note) async {
        final ok = await p.refuse(widget.id, code: code, note: note);
        return (ok: ok, code: p.actionCode, message: p.actionError);
      },
    );
    if (!mounted) return;
    setState(() => _refusing = false);
    switch (result) {
      case RefusalDialogResult.refused:
        AppSnackBar.showOn(
          messenger,
          'Mise en ligne refusée',
          kind: SnackKind.success,
        );
        context.go('/admin/salon-validations');
      case RefusalDialogResult.conflict:
        // The bar says it: the request was decided elsewhere.
        break;
      case RefusalDialogResult.cancelled:
        // What the dialog said stayed in the dialog.
        p.clearActionError();
    }
  }

  /// The fix is on the salon's page — « Lever la suspension », « Marquer
  /// payé ». Back from it, the request is read again: this screen's State
  /// waited under the pushed page (no initState), and nothing there re-reads
  /// it, so « Valider » stayed disabled on what the admin had just fixed.
  Future<void> _openSalonPage() async {
    await context.push('/admin/providers/${Uri.encodeComponent(widget.id)}');
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminSalonValidationDetailProvider>();
    return AdminScaffold(
      title: AdminSalonValidationDetailScreen.title,
      showBack: true,
      actions: [
        IconButton(
          tooltip: 'Rafraîchir',
          icon: const Icon(Icons.refresh, size: AppTheme.iconS),
          onPressed: _load,
        ),
      ],
      child: _body(context, p),
    );
  }

  Widget _body(BuildContext context, AdminSalonValidationDetailProvider p) {
    // Everything the provider holds is ANOTHER request's until it holds this
    // screen's id (B9.8) — its detail, its error, its states.
    final mine = p.id == widget.id;
    if (mine && p.unavailable) {
      return const SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.spacingL),
        child: AdminValidationUnavailable(),
      );
    }
    if (mine &&
        p.detail == null &&
        !p.isLoading &&
        p.errorCode == 'not_found') {
      return EmptyState(
        icon: Icons.search_off,
        title: 'Demande introuvable',
        description: 'Aucun salon ne correspond à ce lien.',
        actionText: 'Voir les salons à valider',
        onAction: () => context.go('/admin/salon-validations'),
      );
    }
    return AppAsyncView<SalonValidationDetail>(
      isLoading: mine && p.isLoading,
      error: mine ? p.error : null,
      data: mine ? p.detail : null,
      isEmpty: (_) => false,
      loading: const SkeletonDetail(sections: 3),
      empty: const SizedBox.shrink(),
      onRetry: _load,
      builder: (context, d) => _detail(context, p, d),
    );
  }

  Widget _detail(
    BuildContext context,
    AdminSalonValidationDetailProvider p,
    SalonValidationDetail d,
  ) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: LayoutBuilder(
              builder: (context, box) {
                final salon = _SalonColumn(detail: d);
                final owner = _OwnerColumn(detail: d);
                if (box.maxWidth < _twoColumnsMinWidth * _textScale(context)) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      salon,
                      const SizedBox(height: AppTheme.spacingL),
                      owner,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: salon),
                    const SizedBox(width: AppTheme.spacingL),
                    Expanded(flex: 2, child: owner),
                  ],
                );
              },
            ),
          ),
        ),
        _DecisionBar(
          detail: d,
          acting: p.acting,
          // A conflict is said here once the dialog has closed; a cancel
          // took what the dialog said with it.
          message: _refusing ? null : p.actionError,
          offerLapsed: p.actionMissing.contains('offer'),
          suspendedAnswer: p.actionCode == 'provider_suspended',
          onApprove: _approve,
          onRefuse: _refuse,
          onOpenSalonPage: _openSalonPage,
        ),
      ],
    );
  }

  /// The OS text size, as a factor: the stacking width grows with it.
  static double _textScale(BuildContext context) {
    final base = AppTextStyles.bodyMedium.fontSize!;
    return MediaQuery.textScalerOf(context).scale(base) / base;
  }
}

// --- the salon ---------------------------------------------------------------

class _SalonColumn extends StatelessWidget {
  const _SalonColumn({required this.detail});

  final SalonValidationDetail detail;

  @override
  Widget build(BuildContext context) {
    final s = detail.salon;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: salonNameOr(s.name, kUnnamedSalon),
          level: 2,
          titleStyle: AppTextStyles.titleLarge,
          children: [
            _Fact('Type', value: _category(s.category)),
            _Fact(
              'Demande',
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusChip.forValidation(detail.validation),
              ),
            ),
            _Fact(
              'Statut du salon',
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusChip.forStatus(s.status),
              ),
            ),
            _Fact('Offre', value: _offer(detail.offer, s.timezone)),
            if ((s.description ?? '').trim().isNotEmpty)
              _Fact('Description', value: s.description!.trim()),
          ],
        ),
        const SizedBox(height: AppTheme.spacingM),
        _Section(
          title: 'Photos',
          children: [_Photos(salon: s)],
        ),
        const SizedBox(height: AppTheme.spacingM),
        _Section(
          title: 'Services et prix',
          children: [_Services(salon: s)],
        ),
        const SizedBox(height: AppTheme.spacingM),
        _Section(
          title: 'Horaires',
          children: [_Hours(salon: s)],
        ),
        const SizedBox(height: AppTheme.spacingM),
        _Section(
          title: 'Adresse et téléphone',
          children: [
            _Fact('Adresse', value: _text(s.address)),
            _Fact('Commune', value: _text(s.commune)),
            _Fact('Ville', value: _text(s.city)),
            _Fact('Pays', value: _text(s.countryCode)),
            _Fact('Position', child: _Pin(salon: s)),
            _Fact('Téléphone', value: _phone(s.phoneNumber)),
            _Fact('Indicatif', value: _callingCode(s.phoneNumber)),
            if ((s.whatsapp ?? '').trim().isNotEmpty)
              _Fact('WhatsApp', value: _phone(s.whatsapp)),
          ],
        ),
      ],
    );
  }

  static String _category(String? key) =>
      key == null ? '—' : (salonCategoryLabel(key) ?? '—');

  static String _offer(SalonSubscription? o, String? tz) {
    if (o == null) return 'Aucune offre : l’essai démarrera à la validation';
    String until(DateTime d) => 'jusqu’au ${_day(d, tz)}';
    return switch (o.status) {
      SalonOfferStatus.trial =>
        'Essai gratuit · ${o.tierLabel} · ${until(o.trialEndsAt)}',
      SalonOfferStatus.paid =>
        o.paidUntil == null
            ? 'Offre ${o.tierLabel} active'
            : 'Offre ${o.tierLabel} active · ${until(o.paidUntil!)}',
      SalonOfferStatus.grace =>
        'Période de grâce · ${o.tierLabel} · ${until(o.graceEndsAt)}',
      SalonOfferStatus.expired =>
        o.unpublishedForBilling ? 'Salon dépublié' : 'Offre expirée',
    };
  }
}

/// The photos, in the salon's order, with the logo first when there is one.
///
/// **`Image.network` with [WebHtmlElementStrategy.prefer], not
/// `TimedCachedImage`** (SYSTEM.md §19). The public bucket's CORS answers a
/// preflight from `https://admin.myweli.com` with 403 and no
/// `Access-Control-Allow-Origin` (checked 2026-11-12), so the console's
/// Flutter Web cannot FETCH a photo's bytes; an `<img>` element needs no
/// CORS. Off the web the parameter is accepted and ignored. The KYC
/// documents are signed URLs on another bucket and are not touched.
///
/// A photo opens in a new tab from the button under it — a named, focusable
/// target with its tooltip (§13.4) — rather than from a tap on the picture.
///
/// **The placeholder shows until the first frame** ([Image.frameBuilder]).
/// `loadingBuilder` would never show it on the web: the `<img>` path reports
/// no progress (it waits for the element's decode, then sends one frame), so
/// its progress stays null and the slot stayed an empty box until the photo
/// arrived.
class _Photos extends StatelessWidget {
  const _Photos({required this.salon});

  final ValidationSalon salon;

  @override
  Widget build(BuildContext context) {
    final logo = salon.logoUrl;
    final photos = salon.imageUrls;
    if (photos.isEmpty && (logo == null || logo.isEmpty)) {
      return Text('Aucune photo', style: _muted);
    }
    return Wrap(
      spacing: AppTheme.spacingM,
      runSpacing: AppTheme.spacingM,
      children: [
        if (logo != null && logo.isNotEmpty)
          _Photo(url: logo, caption: 'Logo', semanticLabel: 'Logo du salon'),
        for (final (i, url) in photos.indexed)
          _Photo(
            url: url,
            caption: 'Photo ${i + 1}',
            semanticLabel: 'Photo ${i + 1} du salon',
          ),
      ],
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({
    required this.url,
    required this.caption,
    required this.semanticLabel,
  });

  final String url;
  final String caption;
  final String semanticLabel;

  /// A thumbnail's side — an image dimension, not spacing (SYSTEM.md §5).
  static const double _side = 144;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _side,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            child: SizedBox.square(
              dimension: _side,
              child: Image.network(
                url,
                width: _side,
                height: _side,
                fit: BoxFit.cover,
                semanticLabel: semanticLabel,
                webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                frameBuilder: (context, child, frame, sync) =>
                    frame == null && !sync ? const _PhotoPlaceholder() : child,
                errorBuilder: (context, error, stack) =>
                    const _PhotoPlaceholder(failed: true),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(child: Text(caption, style: AppTextStyles.bodySmall)),
              IconButton(
                tooltip: 'Ouvrir « $caption » dans un nouvel onglet',
                icon: const Icon(Icons.open_in_new, size: AppTheme.iconS),
                onPressed: () => openExternalUrl(context, url),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Where a photo is not (yet) — a tinted square and a glyph, the tokens'
/// colours; said in words to a screen reader when it failed.
class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({this.failed = false});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: failed ? 'Photo indisponible' : null,
      child: ColoredBox(
        color: AppColors.surfaceVariant,
        child: Center(
          child: Icon(
            failed ? Icons.broken_image_outlined : Icons.image_outlined,
            size: AppTheme.iconL,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _Services extends StatelessWidget {
  const _Services({required this.salon});

  final ValidationSalon salon;

  @override
  Widget build(BuildContext context) {
    if (salon.services.isEmpty) return Text('Aucun service', style: _muted);
    return Column(
      children: [
        for (final (i, s) in salon.services.indexed) ...[
          if (i > 0) const SizedBox(height: AppTheme.spacingS),
          LabelValueRow(
            label: [
              s.name.trim().isEmpty ? '—' : s.name.trim(),
              if (s.durationMinutes != null)
                Formatters.formatDuration(s.durationMinutes!),
              // Hidden from booking — and not counted by the go-live gate.
              if (!s.active) 'masqué',
            ].join(' · '),
            value: s.price == null
                ? 'prix non renseigné'
                : Formatters.formatPriceRange(
                    s.price!.toDouble(),
                    s.priceMax?.toDouble(),
                    currency: salon.currency,
                  ),
          ),
        ],
      ],
    );
  }
}

class _Hours extends StatelessWidget {
  const _Hours({required this.salon});

  final ValidationSalon salon;

  static const _days = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche',
  ];

  @override
  Widget build(BuildContext context) {
    if (salon.weeklyHours.isEmpty) {
      return Text('Horaires non renseignés', style: _muted);
    }
    return Column(
      children: [
        for (var day = 0; day < 7; day++) ...[
          if (day > 0) const SizedBox(height: AppTheme.spacingXS),
          LabelValueRow(
            label: _days[day],
            value: _windows(salon.weeklyHours[day] ?? const []),
          ),
        ],
      ],
    );
  }

  /// « 09:00 – 12:00, 14:00 – 18:00 », or « Fermé ». Only the time of day of
  /// a window is significant, as the salon wrote it — no zone conversion.
  static String _windows(List<ValidationOpeningWindow> windows) {
    final open = [
      for (final w in windows)
        if (w.isAvailable && w.start != null && w.end != null)
          '${Formatters.formatHourMinute(w.start!.hour, w.start!.minute)} – '
              '${Formatters.formatHourMinute(w.end!.hour, w.end!.minute)}',
    ];
    return open.isEmpty ? 'Fermé' : open.join(', ');
  }
}

/// The pin's coordinates and the link that shows them on a map, or — no pin
/// — the sentence that says so (the go-live gate needs one).
class _Pin extends StatelessWidget {
  const _Pin({required this.salon});

  final ValidationSalon salon;

  @override
  Widget build(BuildContext context) {
    final lat = salon.latitude;
    final lng = salon.longitude;
    if (lat == null || lng == null) {
      return Text('Aucune position sur la carte', style: _body);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
          style: _body,
        ),
        const SizedBox(height: AppTheme.spacingXS),
        AppButton(
          text: 'Ouvrir dans OpenStreetMap',
          icon: Icons.map_outlined,
          type: AppButtonType.secondary,
          isFullWidth: false,
          onPressed: () => openExternalUrl(
            context,
            AdminSalonValidationDetailScreen.openStreetMapUrl(lat, lng),
          ),
        ),
      ],
    );
  }
}

// --- the owner ---------------------------------------------------------------

class _OwnerColumn extends StatelessWidget {
  const _OwnerColumn({required this.detail});

  final SalonValidationDetail detail;

  @override
  Widget build(BuildContext context) {
    final o = detail.owner;
    final tz = detail.salon.timezone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: 'Propriétaire',
          children: o == null
              ? [
                  // The server's own sentence for a validation it refuses
                  // (409 `no_owner`), said before the button is pressed.
                  InlineFeedback(AdminService.sentenceFor('no_owner')),
                ]
              : [
                  _Fact('Nom', value: _text(o.name)),
                  if ((o.businessName ?? '').trim().isNotEmpty)
                    _Fact('Entreprise', value: o.businessName!.trim()),
                  if ((o.email ?? '').trim().isNotEmpty)
                    _Fact('E-mail', value: o.email!.trim()),
                  if ((o.phone ?? '').trim().isNotEmpty)
                    _Fact('Téléphone', value: _phone(o.phone)),
                  if ((o.email ?? '').trim().isEmpty &&
                      (o.phone ?? '').trim().isEmpty)
                    _Fact('Contact', value: _text(o.contact)),
                  _Fact('Ancienneté du compte', value: _age(o, tz)),
                  _Fact('KYC', child: _Kyc(owner: o)),
                ],
        ),
        const SizedBox(height: AppTheme.spacingM),
        _Section(
          title: 'Autres salons du propriétaire',
          children: [_OtherSalons(owner: o)],
        ),
        const SizedBox(height: AppTheme.spacingM),
        _Section(
          title: 'Historique de la demande',
          children: [_History(detail: detail)],
        ),
      ],
    );
  }

  /// « 12 jours · depuis le 31 oct. 2026 ».
  static String _age(ValidationOwner o, String? tz) {
    final days = o.accountAgeDays;
    final since = o.createdAt == null
        ? null
        : 'depuis le ${_day(o.createdAt!, tz)}';
    return [
      if (days != null) Formatters.count(days, 'jour', 'jours'),
      ?since,
    ].join(' · ').ifEmpty('—');
  }
}

/// « aucun document », or « N documents · {status} » and its link — the link
/// only when documents exist: almost every account reads « pending » without
/// having sent anything (§4.3).
class _Kyc extends StatelessWidget {
  const _Kyc({required this.owner});

  final ValidationOwner owner;

  @override
  Widget build(BuildContext context) {
    final n = owner.kycDocCount;
    if (n <= 0) return Text('aucun document', style: _body);
    final status = StatusLabels.ofRaw(owner.kycStatus) ?? '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${Formatters.count(n, 'document', 'documents')} · $status',
          style: _body,
        ),
        AppButton(
          text: 'Ouvrir le dossier KYC',
          type: AppButtonType.text,
          isFullWidth: false,
          onPressed: () => context.push(
            '/admin/kyc/${Uri.encodeComponent(owner.accountId)}',
          ),
        ),
      ],
    );
  }
}

class _OtherSalons extends StatelessWidget {
  const _OtherSalons({required this.owner});

  final ValidationOwner? owner;

  @override
  Widget build(BuildContext context) {
    final salons = owner?.otherSalons ?? const <ValidationOwnedSalon>[];
    if (salons.isEmpty) return Text('Aucun autre salon', style: _muted);
    // Its own Material: a tile draws its ink on the nearest one, and the
    // card's white box would hide it.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          for (final s in salons)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                salonNameOr(s.name, kUnnamedSalon),
                style: AppTextStyles.bodyMedium,
              ),
              trailing: StatusChip.forStatus(s.status),
              onTap: () =>
                  context.push('/admin/providers/${Uri.encodeComponent(s.id)}'),
            ),
        ],
      ),
    );
  }
}

/// The request's history, oldest first: each request, each decision, the
/// refusal's code (final or not) and its note.
class _History extends StatelessWidget {
  const _History({required this.detail});

  final SalonValidationDetail detail;

  @override
  Widget build(BuildContext context) {
    final events = detail.events;
    if (events.isEmpty) {
      return Text(
        detail.validation == null
            ? ValidationLabels.neverAsked
            : 'Aucun événement',
        style: _muted,
      );
    }
    final tz = detail.salon.timezone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, e) in events.indexed) ...[
          if (i > 0) const Divider(height: AppTheme.spacingL),
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ValidationLabels.eventKind(e.kind),
                  style: AppTextStyles.titleSmall,
                ),
                Text(
                  [
                    if (e.at != null) _moment(e.at!, tz),
                    if ((e.by ?? '').isNotEmpty) 'par ${e.by}',
                  ].join(' · ').ifEmpty('—'),
                  style: _muted,
                ),
                if (e.refusalCode != null)
                  Text(
                    'Motif : ${ValidationLabels.refusalName(e.refusalCode)}'
                    '${ValidationLabels.isFinal(e.refusalCode!) ? ' · définitif' : ''}',
                    style: _body,
                  ),
                if ((e.refusalNote ?? '').trim().isNotEmpty)
                  Text('Note : « ${e.refusalNote!.trim()} »', style: _body),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// --- the decision -----------------------------------------------------------

/// The sticky bar (§4.3): the decision's buttons, and above them, in words,
/// why one is disabled, what is left to finish, or what the last attempt
/// answered. Nothing to decide — validated and live, never asked — and
/// nothing to say: no bar.
class _DecisionBar extends StatelessWidget {
  const _DecisionBar({
    required this.detail,
    required this.acting,
    required this.message,
    required this.offerLapsed,
    required this.suspendedAnswer,
    required this.onApprove,
    required this.onRefuse,
    required this.onOpenSalonPage,
  });

  final SalonValidationDetail detail;
  final bool acting;

  /// The last decision's failure, worded.
  final String? message;

  /// The last validation found the offer lapsed (`missing` holds `offer`).
  final bool offerLapsed;

  /// The last validation found the salon suspended.
  final bool suspendedAnswer;
  final VoidCallback onApprove;
  final VoidCallback onRefuse;
  final VoidCallback onOpenSalonPage;

  @override
  Widget build(BuildContext context) {
    final canRefuse = detail.canRefuse;
    final hasApprove = detail.approveFrom != null;
    final suspended = detail.salon.isSuspended;
    if (!canRefuse && !hasApprove && message == null) {
      return const SizedBox.shrink();
    }
    // Where the fix is: lifting a suspension and « Marquer payé » are both
    // on the salon's page.
    final salonPageHelps =
        (hasApprove && suspended) || offerLapsed || suspendedAnswer;
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: const BoxDecoration(
        color: AppColors.secondary,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasApprove && detail.isFinishing)
            const _BarNote(
              icon: Icons.info_outline,
              text:
                  '${ValidationLabels.finishing} : la validation est '
                  'enregistrée, mais le salon n’est pas encore en ligne.',
            ),
          // Disabled, and why — in words and with a glyph, not by the grey
          // of the button alone (§13.6). The spec's own sentence.
          if (hasApprove && suspended && !suspendedAnswer)
            _BarNote(
              icon: Icons.pause_circle_outline,
              text: AdminService.sentenceFor('provider_suspended'),
            ),
          if (message != null) InlineFeedback(message),
          if (salonPageHelps)
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                text: 'Ouvrir la fiche du salon',
                type: AppButtonType.text,
                isFullWidth: false,
                onPressed: onOpenSalonPage,
              ),
            ),
          if (canRefuse || hasApprove)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.spacingS),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppTheme.spacingM,
                runSpacing: AppTheme.spacingS,
                children: [
                  if (canRefuse)
                    OutlinedButton(
                      // Destructive (§15): the error colour, line and label.
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        minimumSize: const Size(0, kMinInteractiveDimension),
                      ),
                      onPressed: acting ? null : onRefuse,
                      child: const Text('Refuser'),
                    ),
                  if (hasApprove)
                    AppButton(
                      text: 'Valider la mise en ligne',
                      isFullWidth: false,
                      isLoading: acting,
                      onPressed: acting || !detail.canApprove
                          ? null
                          : onApprove,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BarNote extends StatelessWidget {
  const _BarNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacingS),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppTheme.iconS, color: AppColors.textSecondary),
          const SizedBox(width: AppTheme.spacingS),
          Expanded(child: Text(text, style: _body)),
        ],
      ),
    );
  }
}

// --- building blocks ---------------------------------------------------------

/// A titled card of facts — the console's bordered box (`radiusMedium`, as
/// `AdminProfileCard`), its title a heading (§13.4).
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.level = 2,
    this.titleStyle,
  });

  final String title;
  final List<Widget> children;
  final int level;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            headingLevel: level,
            child: Text(title, style: titleStyle ?? AppTextStyles.titleSmall),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          ...children,
        ],
      ),
    );
  }
}

/// A label over its value (or over a widget: a chip, a link).
class _Fact extends StatelessWidget {
  const _Fact(this.label, {this.value, this.child})
    : assert(value != null || child != null, 'a value or a widget');

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _label),
          child ?? Text(value!, style: _body),
        ],
      ),
    );
  }
}

final TextStyle _label = AppTextStyles.bodySmall.copyWith(
  color: AppColors.textTertiary,
);
const TextStyle _body = AppTextStyles.bodyMedium;
final TextStyle _muted = AppTextStyles.bodyMedium.copyWith(
  color: AppColors.textTertiary,
);

String _text(String? v) => (v == null || v.trim().isEmpty) ? '—' : v.trim();

/// « 31 oct. 2026 » in the salon's time.
String _day(DateTime d, String? tz) =>
    Formatters.formatDateCompact(toSalonTime(d, tz: tz));

/// « 12 nov. 2026 à 09:00 » in the salon's time.
String _moment(DateTime d, String? tz) {
  final t = toSalonTime(d, tz: tz);
  return '${Formatters.formatDateCompact(t)} à ${Formatters.formatTime(t)}';
}

/// The phone as stored, Côte d'Ivoire's grouped in pairs; its calling code
/// stays first either way — what tells Dakar from Abidjan (decision 123).
String _phone(String? raw) {
  final v = raw?.trim() ?? '';
  return v.isEmpty ? '—' : Formatters.formatPhoneNumber(v);
}

/// « +225 », or why there is none: a number stored without its calling code
/// (an older row) cannot say which country it dials.
String _callingCode(String? raw) {
  final v = (raw ?? '').replaceAll(' ', '');
  if (v.isEmpty) return '—';
  if (!v.startsWith('+')) return 'absent du numéro';
  final code = PhoneNumbering.callingCodeOf(v.substring(1));
  return code.isEmpty ? 'inconnu' : '+$code';
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
