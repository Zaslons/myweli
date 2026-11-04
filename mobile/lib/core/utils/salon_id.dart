/// A salon's id (B9.9, decision 33 — docs/design/hygiene-batch9.md §2.8).
///
/// A `String` at run time (JSON, `Equatable`, map keys and URLs see no
/// difference), and a `SalonId` goes wherever a `String` does (Q20). The
/// other way is refused: a bare `String` — an account id, above all — no
/// longer fills a salon slot. That is the R6 blind spot
/// (r6-salon-id-pin.md §3): `createService(account.id, …)` passed the pin and
/// now fails to compile.
///
/// Born in few places — a model's `fromJson`, the session's selected salon,
/// the doubles' data — and `salon_id_type_test.dart` holds that list.
extension type const SalonId(String value) implements String {
  /// No salon resolved — the empty id the screens sent before the type
  /// (`activeSalonId ?? ''`), named rather than repeated. It IS the empty
  /// string, so every place that sent `''` behaves exactly as before, and
  /// `resolveActingSalonId` skips it as it skipped `''`.
  static const none = SalonId('');
}
