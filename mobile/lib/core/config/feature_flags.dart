/// Central switches for features that are not part of the current V1 release.
///
/// The eight provider "feature" modules under `screens/provider/features/`
/// (loyalty programs, inventory, payroll, reports/analytics, client database,
/// booking journal, online booking, WhatsApp notifications) are **V2/V3**.
/// They stay in the tree but are gated off so they cannot ship in V1 — each
/// screen short-circuits to a "coming soon" placeholder while this is false.
/// Flip to enable when those phases land.
class FeatureFlags {
  const FeatureFlags._();

  static const bool futureProviderFeatures = false;
}
