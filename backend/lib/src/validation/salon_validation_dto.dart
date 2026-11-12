/// The `validation` object (docs/design/salon-go-live-approval.md §3.5) —
/// ONE shape for every read that carries it: the 202 of a request, the
/// owner's `/me/provider` and `/me/salons`, the admin's answers.
///
/// `{ state, submittedAt?, decidedAt?, wentLive, offerLive?, refusal?:
/// { code, note?, final } }`. The admin's id ([SalonValidation.decidedBy]) is
/// never in it: a salon never sees who decided. Authenticated reads only —
/// never `providers.data`, which is the public payload (§2.2).
library;

import 'salon_validation_repository.dart';

Map<String, dynamic> salonValidationJson(
  SalonValidation v, {
  bool? offerLive,
}) => {
  'state': v.state,
  if (v.submittedAt != null) 'submittedAt': v.submittedAt!.toIso8601String(),
  if (v.decidedAt != null) 'decidedAt': v.decidedAt!.toIso8601String(),
  // Tells « finishing » (approved, never live) from « was live » (§6.1).
  'wentLive': v.wentLive,
  // Only for a validated salon that is not live: « Plus en ligne : impayé »
  // against « Remettre en ligne » (§3.5). The caller decides when it is
  // meaningful and passes it then.
  'offerLive': ?offerLive,
  if (v.state == ValidationStates.refused && v.refusalCode != null)
    'refusal': {
      'code': v.refusalCode,
      'note': ?v.refusalNote,
      'final': v.isFinalRefusal,
    },
};
