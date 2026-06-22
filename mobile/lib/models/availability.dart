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

  /// Recurring unavailable windows within a working day (e.g. lunch), keyed by
  /// weekday (0=Monday..6=Sunday). Empty = no breaks.
  final Map<int, List<TimeSlot>> breaks;

  const Availability({
    required this.providerId,
    required this.weeklySchedule,
    required this.blockedDates,
    this.bufferMinutes = 0,
    this.breaks = const {},
  });

  @override
  List<Object?> get props =>
      [providerId, weeklySchedule, blockedDates, bufferMinutes, breaks];

  Availability copyWith({
    String? providerId,
    Map<int, List<TimeSlot>>? weeklySchedule,
    List<DateTime>? blockedDates,
    int? bufferMinutes,
    Map<int, List<TimeSlot>>? breaks,
  }) {
    return Availability(
      providerId: providerId ?? this.providerId,
      weeklySchedule: weeklySchedule ?? this.weeklySchedule,
      blockedDates: blockedDates ?? this.blockedDates,
      bufferMinutes: bufferMinutes ?? this.bufferMinutes,
      breaks: breaks ?? this.breaks,
    );
  }

  static Map<String, dynamic> _scheduleToJson(Map<int, List<TimeSlot>> m) =>
      m.map((key, value) => MapEntry(
            key.toString(),
            value.map((slot) => slot.toJson()).toList(),
          ));

  static Map<int, List<TimeSlot>> _scheduleFromJson(Map? json) {
    if (json == null) return const {};
    return json.map((key, value) => MapEntry(
          int.parse(key as String),
          (value as List)
              .map((slot) => TimeSlot.fromJson(slot as Map<String, dynamic>))
              .toList(),
        ));
  }

  Map<String, dynamic> toJson() {
    return {
      'providerId': providerId,
      'weeklySchedule': _scheduleToJson(weeklySchedule),
      'blockedDates': blockedDates.map((d) => d.toIso8601String()).toList(),
      'bufferMinutes': bufferMinutes,
      'breaks': _scheduleToJson(breaks),
    };
  }

  factory Availability.fromJson(Map<String, dynamic> json) {
    return Availability(
      providerId: json['providerId'] as String,
      weeklySchedule: _scheduleFromJson(json['weeklySchedule'] as Map),
      blockedDates: (json['blockedDates'] as List)
          .map((d) => DateTime.parse(d as String))
          .toList(),
      bufferMinutes: (json['bufferMinutes'] as num?)?.toInt() ?? 0,
      breaks: _scheduleFromJson(json['breaks'] as Map?),
    );
  }
}
