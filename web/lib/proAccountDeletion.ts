import type { DocumentDate, DocumentRoute } from './legal';

/// `/pro/suppression-compte` — how a salon account (MyWeli Pro) is deleted on
/// the web, the URL Google Play's Data safety form takes for MyWeli Pro
/// (docs/design/web-pro-account-deletion.md, B0.19, decisions 137–140).
///
/// **Not in `LEGAL_ROUTES`, on purpose.** That list feeds every page's footer
/// and is half of the apps' five-link contract (decision 73): this page is
/// opened by no app and linked from none of the five. It renders through the
/// same shell (`DocumentPage`) with its own route and its own date.
export const PRO_ACCOUNT_DELETION: DocumentRoute = {
  slug: '/pro/suppression-compte',
  h1: 'Supprimer votre compte MyWeli Pro',
  title: 'Supprimer votre compte MyWeli Pro',
  description:
    'Comment supprimer votre compte MyWeli Pro sur le web, sans l’application, ' +
    'et ce que deviennent votre compte, votre salon et vos données.',
};

/// The page's own date, **never `LEGAL_UPDATED_AT`**: the shared legal date
/// moves with the four legal documents, and this page must neither move with
/// them nor move them. A change to what this page says moves this date, in the
/// same PR, as the legal date's rule asks of the four.
export const PRO_ACCOUNT_DELETION_UPDATED_AT: DocumentDate = {
  iso: '2026-11-14',
  label: '14 novembre 2026',
};
