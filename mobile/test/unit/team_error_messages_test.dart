import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/team_error_messages.dart';

/// The team & offers copy table (team access R3 §7) after the companion path
/// (docs/design/pro-companion-path.md §2.2): every refusal states a fact, and
/// none sends the salon to choose, upgrade, activate or pay for an offer.
void main() {
  test('the offer-related codes read the spec\'s exact sentences', () {
    expect(
      teamErrorMessage('offer_required'),
      'Vous pourrez inviter votre équipe une fois votre salon en ligne.',
    );
    expect(
      teamErrorMessage('seat_limit'),
      'Toutes les places de votre offre sont occupées.',
    );
    expect(
      teamErrorMessage('trial_used'),
      'Votre essai gratuit a déjà été utilisé.',
    );
    expect(
      teamErrorMessage('reseau_required'),
      'L’ajout de salons n’est pas disponible avec l’offre actuelle.',
    );
    expect(
      teamErrorMessage('salon_limit'),
      'Nombre maximal de salons atteint.',
    );
    expect(
      teamErrorMessage('demo_account_locked'),
      'Compte de démonstration — cette action est désactivée.',
    );
  });

  test('offer_required: setup and expired get different sentences', () {
    expect(
      inviteOfferRequiredMessage(offerExists: false),
      'Vous pourrez inviter votre équipe une fois votre salon en ligne.',
    );
    expect(
      inviteOfferRequiredMessage(offerExists: true),
      'Les invitations sont indisponibles : l’offre de votre salon n’est '
      'plus active.',
    );
  });

  test('the publish refusal sentence', () {
    expect(
      publishOfferInactiveMessage,
      'La mise en ligne est indisponible : l’offre de votre salon n’est plus '
      'active.',
    );
  });

  test('no sentence in the table points to a way to obtain an offer', () {
    const codes = [
      'member_exists',
      'offer_required',
      'seat_limit',
      'invite_rate_limited',
      'owner_protected',
      'invitation_expired',
      'invalid_role',
      'artist_required',
      'artist_not_found',
      'trial_used',
      'not_found',
      'reseau_required',
      'salon_limit',
      'not_a_member',
      'forbidden',
      'demo_account_locked',
      null,
    ];
    final sentences = [
      for (final c in codes) teamErrorMessage(c),
      inviteOfferRequiredMessage(offerExists: true),
      publishOfferInactiveMessage,
    ];
    for (final s in sentences) {
      for (final cta in [
        'Contactez',
        'Passez à',
        'Choisissez votre offre',
        'Choisissez d’abord',
        'activer votre offre',
        'Mon abonnement',
        'myweli.com',
        'aller plus loin',
      ]) {
        expect(s, isNot(contains(cta)), reason: '« $s » carries « $cta »');
      }
    }
  });
}
