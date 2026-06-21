import 'package:equatable/equatable.dart';

enum AppNotificationType {
  bookingConfirmed,
  depositReceived,
  reminder,
  reschedule,
  cancellation,
  reviewRequest,
  general,
}

class AppNotification extends Equatable {
  final String id;
  final AppNotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  /// Optional in-app deep link to open when tapped (e.g. '/bookings').
  final String? route;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.route,
  });

  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      createdAt: createdAt,
      read: read ?? this.read,
      route: route,
    );
  }

  @override
  List<Object?> get props => [id, type, title, body, createdAt, read, route];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'body': body,
      'createdAt': createdAt.toIso8601String(),
      'read': read,
      'route': route,
    };
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: AppNotificationType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => AppNotificationType.general,
      ),
      title: json['title'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      read: json['read'] as bool? ?? false,
      route: json['route'] as String?,
    );
  }
}
