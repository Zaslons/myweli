/// Which consumer sign-in methods are enabled (`AUTH_METHODS` env, comma-
/// separated). The launch config disables the costly SMS path
/// (`google,apple,email`); flipping a method back on is one env change.
/// Design: docs/design/auth-social-email.md §14.
class AuthMethods {
  const AuthMethods(this.enabled, {this.explicit = false});

  /// Parse a comma-separated list; null/empty → [defaults] (not [explicit]).
  factory AuthMethods.parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const AuthMethods(defaults);
    return AuthMethods(
      raw
          .split(',')
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toSet(),
      explicit: true,
    );
  }

  static const Set<String> defaults = {'google', 'apple', 'email', 'phone'};

  final Set<String> enabled;

  /// Whether the set came from an explicit `AUTH_METHODS` value. Prod
  /// fail-fast on missing per-method config applies only then — an unset
  /// `AUTH_METHODS` keeps a legacy deploy booting (new methods fail closed).
  final bool explicit;

  bool contains(String method) => enabled.contains(method);
}
