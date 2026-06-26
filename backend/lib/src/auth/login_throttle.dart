/// Process-local failed-login throttle: after [maxAttempts] failures a key is
/// locked for [lockout]. Single-instance V1 (admin login volume is tiny); move
/// to a shared store if the API is ever horizontally scaled.
class LoginThrottle {
  LoginThrottle({
    this.maxAttempts = 5,
    this.lockout = const Duration(minutes: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxAttempts;
  final Duration lockout;
  final DateTime Function() _clock;
  final Map<String, ({int count, DateTime? until})> _state = {};

  bool isLocked(String key) {
    final s = _state[key];
    if (s?.until == null) return false;
    if (_clock().toUtc().isAfter(s!.until!)) {
      _state.remove(key);
      return false;
    }
    return true;
  }

  void recordFailure(String key) {
    final count = (_state[key]?.count ?? 0) + 1;
    _state[key] = (
      count: count,
      until: count >= maxAttempts ? _clock().toUtc().add(lockout) : null,
    );
  }

  void reset(String key) => _state.remove(key);
}
