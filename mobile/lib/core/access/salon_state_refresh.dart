/// What « Configuration » asks of the session once the salon's state moved
/// (B0.18 — docs/design/salon-go-live-approval.md §6.2, « Refresh points »).
///
/// The salon's go-live state has two holders in the Pro app:
///
/// - **the session** (`ProAuthProvider`): the acting salon's state from
///   every GET /me/provider it makes (cold start, refresh, switch), shown by
///   the home card « Configurer mon profil »; and « Mes salons » (GET
///   /me/salons), one line per salon in the picker;
/// - **« Configuration »** (`ProOnboardingProvider`): the state from its own
///   GET /me/provider (one of its load's six reads) and from the publish's
///   answer.
///
/// They stay in step because every event that moves the state makes BOTH
/// re-read the server, from ONE place: `ProOnboardingProvider.publish`
/// takes the answer for « Configuration » and asks the session, through
/// this, to re-read its two copies. `ProAuthProvider` is the app's; a test
/// passes a fake that counts.
///
/// **Again, after any read already out.** A read the session sent before the
/// submit (a « Réessayer », the picker opening, « Configuration »'s own
/// refresh points) may have been answered before the change; joining it, or
/// skipping because one is out, would keep the old state. Each method waits
/// for that read, then reads once more.
abstract interface class SalonStateRefresh {
  /// GET /me/provider again (`refreshMembership`): the acting salon's state,
  /// the home card's.
  Future<void> rereadMembership();

  /// GET /me/salons again (`loadMySalons`): every salon's line, the
  /// picker's.
  Future<void> rereadMySalons();
}
