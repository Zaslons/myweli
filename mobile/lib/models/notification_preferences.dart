import 'package:equatable/equatable.dart';

/// Per-user notification opt-out prefs (FR-NOTIF-004) — mirrors the backend
/// `NotificationPreferences`. All default on; the server respects them at send
/// time. Design: docs/design/notification-preferences.md.
class NotificationPreferences extends Equatable {
  const NotificationPreferences({
    this.reminders = true,
    this.marketing = true,
    this.push = true,
  });

  /// 24h/2h appointment reminders.
  final bool reminders;

  /// Marketing/promotional messages.
  final bool marketing;

  /// Device push notifications.
  final bool push;

  NotificationPreferences copyWith({
    bool? reminders,
    bool? marketing,
    bool? push,
  }) =>
      NotificationPreferences(
        reminders: reminders ?? this.reminders,
        marketing: marketing ?? this.marketing,
        push: push ?? this.push,
      );

  Map<String, dynamic> toJson() => {
        'reminders': reminders,
        'marketing': marketing,
        'push': push,
      };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        reminders: json['reminders'] as bool? ?? true,
        marketing: json['marketing'] as bool? ?? true,
        push: json['push'] as bool? ?? true,
      );

  @override
  List<Object?> get props => [reminders, marketing, push];
}
