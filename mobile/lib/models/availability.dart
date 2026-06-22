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

  /// Minutes kept free between two appointments (cleanup/setup). 0 = none.
  final int bufferMinutes;

  const Availability({
    required this.providerId,
    required this.weeklySchedule,
    required this.blockedDates,
    this.bufferMinutes = 0,
  });

  @override
  List<Object?> get props =>
      [providerId, weeklySchedule, blockedDates, bufferMinutes];

  Availability copyWith({
    String? providerId,
    Map<int, List<TimeSlot>>? weeklySchedule,
    List<DateTime>? blockedDates,
    int? bufferMinutes,
  }) {
    return Availability(
      providerId: providerId ?? this.providerId,
      weeklySchedule: weeklySchedule ?? this.weeklySchedule,
      blockedDates: blockedDates ?? this.blockedDates,
      bufferMinutes: bufferMinutes ?? this.bufferMinutes,
    );
  }

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
      'bufferMinutes': bufferMinutes,
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
      bufferMinutes: (json['bufferMinutes'] as num?)?.toInt() ?? 0,
    );
  }
}
