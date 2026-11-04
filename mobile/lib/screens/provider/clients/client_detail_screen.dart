import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/forms/field_errors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/external_link.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_numbering.dart';
import '../../../core/utils/salon_id.dart';
import '../../../core/utils/salon_time.dart';
import '../../../core/utils/status_labels.dart';
import '../../../core/utils/text_fit.dart';
import '../../../core/utils/validators.dart';
import '../../../models/appointment.dart';
import '../../../models/salon_client.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_clients_provider.dart';
import '../../../widgets/common/app_async_view.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_chip.dart';
import '../../../widgets/common/app_skeleton.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/inline_feedback.dart';
import '../../../widgets/common/phone_number_field.dart';

/// The client card (module `clients` C1c, docs/design/clients-c1.md §5):
/// identity + call/WhatsApp actions, tags, salon-scoped stats, upcoming
/// booking, team-only notes, visit history, and « Nouveau rendez-vous »
/// prefilled into manual booking.
class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final String clientId;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  SalonId get _providerId {
    final auth = context.read<ProAuthProvider>();
    return auth.activeSalonId ?? SalonId.none;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProClientsProvider>().loadCard(_providerId, widget.clientId);
    });
  }

  /// Another client on the same route. go_router keys a page by its route
  /// pattern, so a card that was not pushed (opened by `go` or a deep link)
  /// keeps this State when « Ouvrir la fiche » replaces it with another
  /// client's — and `initState` does not run again. Seen in the test of that
  /// action: the replaced card went on showing the first client.
  @override
  void didUpdateWidget(ClientDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientId == widget.clientId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProClientsProvider>().loadCard(_providerId, widget.clientId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final clients = context.watch<ProClientsProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Fiche client')),
      body: _body(clients),
    );
  }

  Widget _body(ProClientsProvider clients) {
    // A card that is not there is the client's state, not a failed read.
    if (clients.cardNotFound) {
      return const EmptyState(
        icon: Icons.person_off_outlined,
        title: 'Client introuvable',
      );
    }
    return AppAsyncView<SalonClientCard>(
      isLoading: clients.cardLoading,
      error: clients.cardError,
      // Another client's, on this screen's first frame: the provider
      // outlives it (B9.8).
      data: clients.cardClientId == widget.clientId ? clients.card : null,
      isEmpty: (_) => false,
      loading: const SkeletonDetail(sections: 3),
      empty: const SizedBox.shrink(),
      onRetry: () => clients.loadCard(_providerId, widget.clientId),
      builder: (context, card) => _card(clients, card),
    );
  }

  Widget _card(ProClientsProvider clients, SalonClientCard card) {
    final client = card.client;
    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      children: [
        _Header(
          client: client,
          onEditTags: () => _openTagSheet(client),
          // Only a number the server's PATCH takes: the card says so
          // (`phoneEditable` — a guest card that has a number; a card linked to
          // an account keeps the account's). Not guessed from `linked` and
          // `phone`: a server from before the change refuses any number, and
          // « Modifier » would fail on every try (phone-leftovers.md §8).
          onEditPhone: client.phoneEditable
              ? () => _openPhoneSheet(client)
              : null,
        ),
        const SizedBox(height: AppTheme.spacingM),
        _StatsStrip(stats: card.stats, lastVisitAt: client.lastVisitAt),
        if (card.upcoming != null) ...[
          const SizedBox(height: AppTheme.spacingM),
          _UpcomingCard(upcoming: card.upcoming!),
        ],
        const SizedBox(height: AppTheme.spacingM),
        _NotesSection(
          notes: card.notes,
          onAdd: (body) => clients.addNote(_providerId, widget.clientId, body),
          onDelete: (noteId) =>
              clients.deleteNote(_providerId, widget.clientId, noteId),
        ),
        const SizedBox(height: AppTheme.spacingM),
        _VisitsSection(visits: clients.visits),
        const SizedBox(height: AppTheme.spacingL),
        AppButton(
          text: 'Nouvelle réservation',
          onPressed: () => context.push(
            '/pro/appointment/new',
            extra: {
              'clientName': client.displayName,
              'clientPhone': client.phone,
            },
          ),
        ),
        const SizedBox(height: AppTheme.spacingL),
      ],
    );
  }

  Future<void> _openTagSheet(SalonClient client) async {
    final clients = context.read<ProClientsProvider>();
    await showModalBottomSheet<void>(
      context: context,
      // Ten tags, a fault and the keyboard are taller than the default 9/16
      // of the screen — the sheet overflowed (B9.7). It scrolls instead.
      isScrollControlled: true,
      builder: (_) => _TagSheet(
        initial: client.tags,
        onSave: (tags) =>
            clients.updateTags(_providerId, widget.clientId, tags),
      ),
    );
  }

  /// « Modifier » under a guest card's number (phone-leftovers.md §8). The
  /// sheet keeps every fault about the number under its field; what it closes
  /// on is said here, on the card.
  Future<void> _openPhoneSheet(SalonClient client) async {
    final clients = context.read<ProClientsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final exit = await showModalBottomSheet<_PhoneSheetExit>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PhoneSheet(
        initial: client.phone ?? '',
        onSave: (phone) =>
            clients.updatePhone(_providerId, widget.clientId, phone),
      ),
    );
    if (!mounted) return;
    switch (exit) {
      case _PhoneUpdated():
        AppSnackBar.showOn(
          messenger,
          'Numéro mis à jour',
          kind: SnackKind.success,
        );
      case _PhoneLinked():
        // Linked to an account since the card was opened: it has been read
        // again and now shows « Numéro du compte client », with no « Modifier ».
        AppSnackBar.showOn(
          messenger,
          'Cette fiche est liée à un compte client : son numéro est celui '
          'du compte.',
        );
      case _OpenCard(:final clientId):
        // In place of this card, not on top of it: the provider holds one open
        // card, and the one below would come back showing the other's.
        context.pushReplacement('/pro/clients/$clientId');
      case null:
        break;
    }
  }
}

/// How the number sheet closed — besides a plain dismissal (`null`).
sealed class _PhoneSheetExit {
  const _PhoneSheetExit();
}

/// The number changed; the card was read again.
class _PhoneUpdated extends _PhoneSheetExit {
  const _PhoneUpdated();
}

/// `client_linked`: the card is linked to an account now — read-only.
class _PhoneLinked extends _PhoneSheetExit {
  const _PhoneLinked();
}

/// « Ouvrir la fiche »: the card that already has the number.
class _OpenCard extends _PhoneSheetExit {
  const _OpenCard(this.clientId);

  final String clientId;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.client,
    required this.onEditTags,
    this.onEditPhone,
  });

  final SalonClient client;
  final VoidCallback onEditTags;

  /// « Modifier » under the number — null unless the card says its number
  /// can be changed ([SalonClient.phoneEditable]).
  final VoidCallback? onEditPhone;

  static const TextStyle _phoneStyle = AppTextStyles.bodyMedium;
  static const double _avatarRadius = 24;

  /// What the avatar and its gap take from the name-and-number column.
  static const double _identityIndent = 2 * _avatarRadius + AppTheme.spacingM;

  /// « Appeler » and « WhatsApp »: two minimum tap targets.
  static const double _actionsWidth = 2 * kMinInteractiveDimension;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // **The number never wraps** (docs/design/amounts-that-fit.md §11
          // Q3, SYSTEM.md §13.3): « Appeler » and « WhatsApp » sit beside it
          // while it fits on one line there, drop under it when it does not,
          // and at very large text the number takes the card's full width.
          // Measured, like the stats strip: it wrapped between its pairs from
          // 1.1× on 360dp (145dp in 136) under a fixed layout.
          LayoutBuilder(
            builder: (context, box) {
              final phone = client.phone == null
                  ? null
                  : Formatters.formatPhoneNumber(client.phone!);
              final fit = TextFit.of(context);
              final needs = phone == null
                  ? 0.0
                  : fit.lineWidth(phone, _phoneStyle) + TextFit.slack;
              final beside = box.maxWidth - _identityIndent - _actionsWidth;
              final alone = box.maxWidth - _identityIndent;

              final number = phone == null
                  ? null
                  // In full — the card is where the number lives
                  // (`maskClientPhone`) — but grouped like every other number
                  // in the app: « +225 07 00 00 01 01 ».
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          phone,
                          style: _phoneStyle.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        // Under the number, what can be done with it
                        // (phone-leftovers.md §8): a guest card's can be
                        // changed; a linked card's is the account's.
                        if (client.linked)
                          Text(
                            'Numéro du compte client',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          )
                        else if (onEditPhone != null)
                          _EditNumberButton(onPressed: onEditPhone!),
                      ],
                    );
              final actions = [
                if (client.phone != null) ...[
                  IconButton(
                    icon: const Icon(Icons.phone),
                    tooltip: 'Appeler',
                    onPressed: () => callPhone(context, client.phone!),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chat),
                    tooltip: 'WhatsApp',
                    onPressed: () => launchUrl(
                      Uri.parse(
                        'https://wa.me/${client.phone!.replaceAll(RegExp(r'[^0-9]'), '')}',
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
              ];
              final numberInColumn = needs <= alone;
              final identity = <Widget>[
                CircleAvatar(
                  radius: _avatarRadius,
                  backgroundColor: AppColors.surfaceVariant,
                  child: Text(
                    client.displayName.isEmpty
                        ? '?'
                        : client.displayName[0].toUpperCase(),
                    style: AppTextStyles.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              client.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleLarge.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (client.linked) ...[
                            const SizedBox(width: AppTheme.spacingXS),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.spacingS,
                                vertical: AppTheme.spacingXS,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSmall,
                                ),
                              ),
                              child: Text(
                                'MyWeli',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (number != null && numberInColumn) number,
                    ],
                  ),
                ),
              ];

              if (needs <= beside) {
                return Row(children: [...identity, ...actions]);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: identity),
                  if (number != null && !numberInColumn) ...[
                    const SizedBox(height: AppTheme.spacingXS),
                    number,
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppTheme.spacingS),
          Wrap(
            spacing: AppTheme.spacingXS,
            runSpacing: AppTheme.spacingXS,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final t in client.tags) AppChip.tag(label: t),
              AppChip.action(
                label: client.tags.isEmpty ? '+ Tags' : 'Modifier',
                onPressed: onEditTags,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// « Modifier » under a guest card's number (phone-leftovers.md §8): a text
/// action aligned with the number it edits, at the 48dp floor (§13.2). Its
/// label names what it edits — the tags' chip on the same card reads
/// « Modifier » too.
class _EditNumberButton extends StatelessWidget {
  const _EditNumberButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(
          kMinInteractiveDimension,
          kMinInteractiveDimension,
        ),
        alignment: Alignment.centerLeft,
      ),
      child: const Text('Modifier', semanticsLabel: 'Modifier le numéro'),
    );
  }
}

/// The number sheet (phone-leftovers.md §8): `PhoneNumberField` prefilled with
/// the card's number, « Enregistrer ». Every fault about the number sits under
/// the field (§14 rule 1) — the rule's on submit, the server's
/// `invalid_phone`, and a number already on another card, which also offers
/// that card. It closes on a change (or none to make) and on `client_linked`.
///
/// While the number is being saved the sheet stays — neither « retour », the
/// scrim nor a drag closes it — and the field is disabled: the answer is about
/// the number shown, and is said in the sheet or on the card it closes onto.
class _PhoneSheet extends StatefulWidget {
  const _PhoneSheet({required this.initial, required this.onSave});

  /// The card's number (E.164).
  final String initial;
  final Future<ClientPhoneRefusal?> Function(String phone) onSave;

  @override
  State<_PhoneSheet> createState() => _PhoneSheetState();
}

class _PhoneSheetState extends State<_PhoneSheet> {
  /// What the field holds, normalized — it emits on edits only, so it starts
  /// as the card's number.
  late String _phone = PhoneNumbering.normalize(widget.initial);

  /// The card's number, as far as the sheet knows — what « nothing to
  /// change » compares with. It starts as the one the sheet opened on (read
  /// from [widget], not [_phone]: a `late` initializer runs at the first read,
  /// after the edits).
  late String _onCard = PhoneNumbering.normalize(widget.initial);
  late final _errors = FieldErrors({'phone': Validators.phoneNumber});
  final _focus = FocusNode();
  bool _busy = false;

  /// A refusal the field has no words for (offline, forbidden…) — in the
  /// sheet, where a snackbar would sit under the scrim (§15).
  String? _failure;

  /// `client_exists`: the card that already has the number, offered as
  /// « Ouvrir la fiche ». Goes as soon as the number is edited.
  String? _takenBy;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Whether the sheet is still on the navigator. Closed under a save by a way
  /// its [PopScope] does not see (a pop from code, the router), it stays
  /// mounted while it animates out — and a pop then would close the next
  /// route: the client card.
  bool get _open => ModalRoute.of(context)?.isActive ?? false;

  Future<void> _save() async {
    setState(() {
      _failure = null;
      _takenBy = null;
    });
    // §14 rule 5: the button is live whatever the field holds, so the press
    // answers — under the field.
    if (!_errors.validate({'phone': _phone})) {
      setState(() {});
      focusFirstError(_errors, {'phone': _focus});
      return;
    }
    if (_phone == _onCard) {
      Navigator.of(context).pop(); // nothing to change
      return;
    }
    final sent = _phone;
    setState(() => _busy = true);
    final refusal = await widget.onSave(sent);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!_open) return;
    if (refusal?.code == 'client_linked') {
      // Linked since it was opened: nothing in the field can be saved now,
      // whichever number it holds.
      Navigator.of(context).pop(const _PhoneLinked());
      return;
    }
    if (_phone != sent) {
      // The answer is about a number the field no longer holds: it is not
      // said about the one it does. A change was made all the same — the
      // card holds [sent] now.
      if (refusal == null) _onCard = sent;
      return;
    }
    if (refusal == null) {
      Navigator.of(context).pop(const _PhoneUpdated());
      return;
    }
    switch (refusal.code) {
      case 'invalid_phone':
        // The server is the authority on the number (BACKEND.md §3.4).
        setState(
          () =>
              _errors.set('phone', 'Saisissez un numéro de téléphone valide.'),
        );
        // Once the field is built enabled again: disabled for the save, it
        // takes no focus until then.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) focusFirstError(_errors, {'phone': _focus});
        });
      case 'client_exists':
        final name = refusal.takenByName;
        setState(() {
          _takenBy = refusal.takenById;
          _errors.set(
            'phone',
            name == null
                ? 'Ce numéro est déjà sur la fiche d’un autre client.'
                : 'Ce numéro est déjà sur la fiche ${Formatters.de(name)}.',
          );
        });
      default:
        setState(() => _failure = refusal.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final takenBy = _takenBy;
    // « retour » and the scrim ask before closing; the sheet's own drag does
    // not ask [PopScope] — while saving, a vertical drag on the sheet is taken
    // here, and goes nowhere. Idle, both close it as any sheet.
    return PopScope(
      canPop: !_busy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Not an action: no « scroll » for a screen reader.
        excludeFromSemantics: true,
        onVerticalDragStart: _busy ? (_) {} : null,
        child: _content(context, takenBy),
      ),
    );
  }

  Widget _content(BuildContext context, String? takenBy) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppTheme.spacingL,
        right: AppTheme.spacingL,
        top: AppTheme.spacingL,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spacingL,
      ),
      // §13.3 — a fault under the field plus « Ouvrir la fiche » at 200 % text
      // is taller than a phone: the sheet scrolls.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Modifier le numéro',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppTheme.spacingXS),
            Text(
              'Les visites de ce client suivent le nouveau numéro.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppTheme.spacingM),
            PhoneNumberField(
              initialValue: widget.initial,
              focusNode: _focus,
              // The number being saved is the one shown.
              enabled: !_busy,
              errorText: _errors['phone'],
              onChanged: (e164) => setState(() {
                _phone = e164;
                _takenBy = null;
                _failure = null;
                _errors.revalidate('phone', e164);
              }),
            ),
            InlineFeedback(_failure),
            if (takenBy != null) ...[
              const SizedBox(height: AppTheme.spacingS),
              AppButton(
                text: 'Ouvrir la fiche',
                type: AppButtonType.secondary,
                onPressed: () => Navigator.of(context).pop(_OpenCard(takenBy)),
              ),
            ],
            const SizedBox(height: AppTheme.spacingM),
            AppButton(
              text: 'Enregistrer',
              isLoading: _busy,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.stats, this.lastVisitAt});

  final SalonClientStats stats;
  final DateTime? lastVisitAt;

  static const TextStyle _valueStyle = AppTextStyles.titleMedium;
  static const TextStyle _labelStyle = AppTextStyles.labelSmall;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<ProAuthProvider>();
    final tiles = <({String label, String value, bool alert})>[
      (label: 'Visites', value: '${stats.visits}', alert: false),
      (
        label: 'Dépensé',
        value: Formatters.formatCurrency(
          stats.spentFcfa.toDouble(),
          currency: auth.salonCurrency,
        ),
        alert: false,
      ),
      (label: 'Absences', value: '${stats.noShows}', alert: stats.noShows >= 2),
      (
        label: 'Dernière',
        value: lastVisitAt == null
            ? '—'
            // Compact: « 13 oct. 2026 » breaks between words. The long
            // « mardi 13 octobre 2026 » broke as « dimanch / e » in this
            // quarter-width tile (pro-screenshot-shoot-fixes.md §2.1).
            : Formatters.formatDateCompact(
                toSalonTime(lastVisitAt!, tz: auth.salonTimezone),
              ),
        alert: false,
      ),
    ];

    // **The widest shape in which every value stays whole** — four across,
    // then 2 × 2, then one per row (docs/design/amounts-that-fit.md §2).
    //
    // This was a text-SIZE rule (« 2 × 2 above 1.1× »), measured on the label
    // « Absences » alone. It could not know the amount or the phone: at 360dp
    // « 180 000 » needs 64.7dp of the tile's 60 at 1.1×, and « 1 250 000 »
    // does not fit at the default size. So the widths are measured, with the
    // same strings and styles the tiles draw. The LayoutBuilder sits OUTSIDE
    // the IntrinsicHeight rows (it cannot answer an intrinsic query), and is
    // what makes the shape re-decide when the width, the text size or the
    // amount changes.
    return LayoutBuilder(
      builder: (context, box) {
        final columns = TextFit.of(context).columns(
          candidates: const [4, 2, 1],
          cellWidth: (n) =>
              (box.maxWidth - (n - 1) * AppTheme.spacingS) / n -
              2 * AppTheme.spacingS,
          texts: [
            for (final t in tiles) ...[
              (text: t.value, style: _valueStyle),
              (text: t.label, style: _labelStyle),
            ],
          ],
        );
        return Column(
          children: [
            for (var i = 0; i < tiles.length; i += columns) ...[
              if (i > 0) const SizedBox(height: AppTheme.spacingS),
              // Equal heights within a row — the dashboard action grid's
              // idiom: divide the row, do not dimension the boxes.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (k, t)
                        in tiles.skip(i).take(columns).indexed) ...[
                      if (k > 0) const SizedBox(width: AppTheme.spacingS),
                      Expanded(child: _tile(t.label, t.value, t.alert)),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _tile(String label, String value, bool alert) => Container(
    padding: const EdgeInsets.all(AppTheme.spacingS),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: _valueStyle.copyWith(
            color: alert ? AppColors.error : AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppTheme.spacingXS),
        Text(
          label,
          style: _labelStyle.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.upcoming});

  final Map<String, dynamic> upcoming;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(
      upcoming['appointmentDate'] as String? ?? '',
    );
    final id = upcoming['id'] as String?;
    return InkWell(
      onTap: id == null ? null : () => context.push('/pro/appointment/$id'),
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PROCHAIN RENDEZ-VOUS',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppTheme.spacingXS),
            Text(
              date == null
                  ? '—'
                  : Formatters.formatDateTime(
                      toSalonTime(
                        date,
                        tz: context.read<ProAuthProvider>().salonTimezone,
                      ),
                    ),
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesSection extends StatefulWidget {
  const _NotesSection({
    required this.notes,
    required this.onAdd,
    required this.onDelete,
  });

  final List<SalonClientNote> notes;
  final Future<bool> Function(String body) onAdd;
  final Future<bool> Function(String noteId) onDelete;

  @override
  State<_NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends State<_NotesSection> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  // A7/§14 — including the save failure, which used to vanish.
  late final _errors = FieldErrors({
    'note': Validators.requiredField('une note'),
  });
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    // §14 rule 5: the button is no longer disabled on an empty box.
    if (!_errors.validate({'note': _controller.text})) {
      setState(() {});
      _focus.requestFocus();
      return;
    }
    setState(() => _busy = true);
    final ok = await widget.onAdd(_controller.text.trim());
    if (mounted) {
      setState(() => _busy = false);
      if (ok) {
        _controller.clear();
      } else {
        // A failure used to be swallowed whole: the note stayed in the box and
        // nothing said why.
        setState(
          () => _errors.set('note', 'Enregistrement impossible. Réessayez.'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notes',
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            'Visible uniquement par votre équipe.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          AppTextField(
            controller: _controller,
            focusNode: _focus,
            hint: 'Ajouter une note…',
            maxLength: 500,
            maxLines: 2,
            errorText: _errors['note'],
            onChanged: (v) => setState(() => _errors.revalidate('note', v)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              text: 'Ajouter',
              isFullWidth: false,
              isLoading: _busy,
              onPressed: _busy ? null : _add,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          if (widget.notes.isEmpty)
            Text(
              'Aucune note pour l’instant.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            for (final n in widget.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTheme.spacingS),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.body,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingXS),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${n.authorName} · '
                            '${Formatters.formatRelative(n.createdAt)}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: 48,
                            ), // §13.2 touch target
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => widget.onDelete(n.id),
                              child: Center(
                                widthFactor: 1,
                                child: Text(
                                  'Supprimer',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textTertiary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _VisitsSection extends StatelessWidget {
  const _VisitsSection({required this.visits});

  final List<Appointment> visits;

  Color _statusColor(AppointmentStatus s) => switch (s) {
    AppointmentStatus.completed => AppColors.success,
    AppointmentStatus.noShow => AppColors.error,
    AppointmentStatus.cancelled => AppColors.textTertiary,
    _ => AppColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Historique des visites',
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          if (visits.isEmpty)
            Text(
              'Aucune visite enregistrée.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            for (final v in visits) _visitRow(context, v),
        ],
      ),
    );
  }

  /// One visit: the date, its amount, its status. Beside each other while the
  /// date's longest word fits next to the two; else the date on its own line
  /// and the two under it (B7.10 — SYSTEM §21 row 96). At 200 % on 360 dp a
  /// seven-digit amount left the date less than « octobre » needs (97 dp),
  /// and it broke inside the word. Measured with [TextFit], never a size
  /// constant; at the default size nothing changes.
  Widget _visitRow(BuildContext context, Appointment v) {
    final date = Formatters.formatDateTime(
      toSalonTime(
        v.appointmentDate,
        tz: context.read<ProAuthProvider>().salonTimezone,
      ),
    );
    final amount = Formatters.formatCurrency(
      v.totalPrice,
      currency: context.read<ProAuthProvider>().salonCurrency,
    );
    final status = StatusLabels.of(v.status);
    final dateStyle = AppTextStyles.bodyMedium.copyWith(
      color: AppColors.textPrimary,
    );
    final amountStyle = AppTextStyles.bodySmall.copyWith(
      color: AppColors.textSecondary,
    );
    final statusStyle = AppTextStyles.bodySmall.copyWith(
      color: _statusColor(v.status),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
      child: LayoutBuilder(
        builder: (context, box) {
          final fit = TextFit.of(context);
          final beside =
              box.maxWidth -
              fit.lineWidth(amount, amountStyle) -
              fit.lineWidth(status, statusStyle) -
              2 * AppTheme.spacingS;
          final figures = [
            Text(amount, style: amountStyle),
            const SizedBox(width: AppTheme.spacingS),
            Text(status, style: statusStyle),
          ];
          if (!fit.holds(beside, [(text: date, style: dateStyle)])) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date, style: dateStyle),
                const SizedBox(height: AppTheme.spacingXS),
                Row(children: figures),
              ],
            );
          }
          return Row(
            children: [
              // The date takes all the width that is left; without this, a
              // date that fits its line exactly ends ON the amount
              // (« 08:007 000 FCFA », seen on the simulator).
              Expanded(child: Text(date, style: dateStyle)),
              const SizedBox(width: AppTheme.spacingS),
              ...figures,
            ],
          );
        },
      ),
    );
  }
}

class _TagSheet extends StatefulWidget {
  const _TagSheet({required this.initial, required this.onSave});

  final List<String> initial;
  final Future<bool> Function(List<String> tags) onSave;

  @override
  State<_TagSheet> createState() => _TagSheetState();
}

class _TagSheetState extends State<_TagSheet> {
  /// The most a client carries, the server's cap.
  static const _maxTags = 10;
  static const _limitFault =
      'Vous avez atteint 10 tags — retirez-en un pour en ajouter.';

  /// A7/§14, on `FieldErrors` since B9.7: the custom-tag field's fault is
  /// asked again as the value changes, where any keystroke used to clear it.
  late final _errors = FieldErrors({'tag': _tagRule});

  /// Read against the tags already chosen: already there, then the limit —
  /// at ten, the limit is what to fix whatever is typed — then empty.
  String? _tagRule(String value) {
    final t = value.trim();
    if (t.isNotEmpty && _tags.contains(t)) return 'Ce tag est déjà ajouté.';
    if (_tags.length >= _maxTags) return _limitFault;
    if (t.isEmpty) return 'Saisissez un tag.';
    return null;
  }

  /// A save that failed — the sheet's outcome, not the field's (SYSTEM §14,
  /// the three slots: in a sheet, `InlineFeedback`). It used to leave the
  /// sheet open and say nothing.
  String? _failure;

  late final List<String> _tags = List.of(widget.initial);
  final _customController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _toggle(String tag) {
    setState(() {
      if (_tags.contains(tag)) {
        _tags.remove(tag);
      } else if (_tags.length < _maxTags) {
        _tags.add(tag);
      } else {
        // The eleventh chip did nothing at all (§14 rule 5): it says why.
        _errors.set('tag', _limitFault);
        return;
      }
      _recheck();
    });
  }

  /// A chip changes the set the rule reads, so a fault on show is asked
  /// again (§14 rule 2). The limit raised with the box empty is answered by
  /// the count alone: « Saisissez un tag. » is for « + ».
  void _recheck() {
    final text = _customController.text;
    if (_errors['tag'] == _limitFault && text.trim().isEmpty) {
      if (_tags.length < _maxTags) _errors.set('tag', null);
    } else {
      _errors.revalidate('tag', text);
    }
  }

  void _addCustom() {
    final text = _customController.text;
    setState(() {
      if (!_errors.validate({'tag': text})) return;
      _tags.add(text.trim());
      _customController.clear();
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final ok = await widget.onSave(_tags);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _failure = 'Enregistrement impossible. Réessayez.';
    });
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final choices = {
      ...salonClientPresetTags,
      ...widget.initial,
      ..._tags,
    }.toList();
    return Padding(
      padding: EdgeInsets.only(
        left: AppTheme.spacingL,
        right: AppTheme.spacingL,
        top: AppTheme.spacingL,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spacingL,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tags',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppTheme.spacingM),
            Wrap(
              spacing: AppTheme.spacingXS,
              runSpacing: AppTheme.spacingXS,
              children: [
                for (final t in choices)
                  AppChip.choice(
                    label: t,
                    selected: _tags.contains(t),
                    onSelected: (_) => _toggle(t),
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingM),
            AppTextField(
              controller: _customController,
              label: 'Tag personnalisé',
              hint: 'Ex : Mariée juin',
              maxLength: 24,
              errorText: _errors['tag'],
              onChanged: (v) => setState(() => _errors.revalidate('tag', v)),
              suffixIcon: IconButton(
                tooltip: 'Ajouter le tag',
                icon: const Icon(Icons.add),
                onPressed: _addCustom,
              ),
            ),
            InlineFeedback(_failure),
            const SizedBox(height: AppTheme.spacingM),
            AppButton(
              text: 'Enregistrer',
              isLoading: _busy,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
