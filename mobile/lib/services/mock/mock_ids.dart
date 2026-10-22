/// The ids the fakes give what they create — a counter, not the clock.
///
/// They were `'<prefix>_${AppClock.now().millisecondsSinceEpoch}'`, and under
/// `freezeClock` every `AppClock.now()` is the same instant: two records made
/// in one test got one id. The second invitation WAS the first, and
/// accepting it accepted the other (docs/design/hygiene-batch9.md §2.5).
abstract final class MockIds {
  static int _last = 0;

  /// `<prefix>_<n>`, never given twice in a run. The seeds' ids carry no
  /// underscore before their number (`service1`, `artist1`, `user1`), so a
  /// made id never meets a seeded one.
  static String next(String prefix) => '${prefix}_${++_last}';
}
