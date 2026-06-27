/// Per-user notification preferences — **opt-out**, default all on. Respected at
/// send time by [BookingNotifier]. Design: docs/design/notification-preferences.md
/// (FR-NOTIF-004).
class NotificationPrefs {
  const NotificationPrefs({
    this.reminders = true,
    this.marketing = true,
    this.push = true,
  });

  /// 24h/2h appointment reminders.
  final bool reminders;

  /// Marketing/promotional messages (ARTCI opt-out).
  final bool marketing;

  /// Device push notifications.
  final bool push;

  Map<String, dynamic> toJson() => {
    'reminders': reminders,
    'marketing': marketing,
    'push': push,
  };
}

abstract interface class NotificationPrefsRepository {
  /// The user's prefs; **all-true defaults** when no row exists.
  Future<NotificationPrefs> get(String userId);

  /// Upsert-merge the provided fields (null = unchanged); returns the result.
  Future<NotificationPrefs> update(
    String userId, {
    bool? reminders,
    bool? marketing,
    bool? push,
  });
}

class InMemoryNotificationPrefsRepository
    implements NotificationPrefsRepository {
  final Map<String, NotificationPrefs> _byUser = {};

  @override
  Future<NotificationPrefs> get(String userId) async =>
      _byUser[userId] ?? const NotificationPrefs();

  @override
  Future<NotificationPrefs> update(
    String userId, {
    bool? reminders,
    bool? marketing,
    bool? push,
  }) async {
    final cur = _byUser[userId] ?? const NotificationPrefs();
    final next = NotificationPrefs(
      reminders: reminders ?? cur.reminders,
      marketing: marketing ?? cur.marketing,
      push: push ?? cur.push,
    );
    _byUser[userId] = next;
    return next;
  }
}
