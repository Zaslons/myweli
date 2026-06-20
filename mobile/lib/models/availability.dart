import 'package:equatable/equatable.dart';

class TimeSlot extends Equatable {
  final DateTime startTime;
  final DateTime endTime;
  final bool isAvailable;

  const TimeSlot({
    required this.startTime,
    required this.endTime,
    required this.isAvailable,
  });

  @override
  List<Object?> get props => [startTime, endTime, isAvailable];

  Map<String, dynamic> toJson() {
    return {
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'isAvailable': isAvailable,
    };
  }

  factory TimeSlot.fromJson(Map<String, dynamic> json) {
    return TimeSlot(
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      isAvailable: json['isAvailable'] as bool,
    );
  }
}

class Availability extends Equatable {
  final String providerId;
  final Map<int, List<TimeSlot>> weeklySchedule; // 0=Monday, 6=Sunday
  final List<DateTime> blockedDates;

  const Availability({
    required this.providerId,
    required this.weeklySchedule,
    required this.blockedDates,
  });

  @override
  List<Object?> get props => [providerId, weeklySchedule, blockedDates];

  Map<String, dynamic> toJson() {
    return {
      'providerId': providerId,
      'weeklySchedule': weeklySchedule.map(
        (key, value) => MapEntry(
          key.toString(),
          value.map((slot) => slot.toJson()).toList(),
        ),
      ),
      'blockedDates': blockedDates.map((d) => d.toIso8601String()).toList(),
    };
  }

  factory Availability.fromJson(Map<String, dynamic> json) {
    return Availability(
      providerId: json['providerId'] as String,
      weeklySchedule: (json['weeklySchedule'] as Map).map(
        (key, value) => MapEntry(
          int.parse(key as String),
          (value as List)
              .map((slot) => TimeSlot.fromJson(slot as Map<String, dynamic>))
              .toList(),
        ),
      ),
      blockedDates: (json['blockedDates'] as List)
          .map((d) => DateTime.parse(d as String))
          .toList(),
    );
  }
}
