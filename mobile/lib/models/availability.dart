import 'package:equatable/equatable.dart';

import '../core/constants/booking_horizons.dart';

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

  /// How far ahead clients may book, in SALON calendar days (A14d).
  ///
  /// Server-enforced for client paths only — the salon's own manual booking and
  /// its own reschedules are exempt, because the salon owns its calendar. The
  /// app uses it to bound the day picker and to explain an empty day honestly;
  /// the server is the authority, and a stale client is simply refused.
  final int bookingHorizonDays;

  /// How soon before a start a client may still book, in minutes (A14d).
  ///
  /// 0 = walk-ins welcome. Was a bare `60` inside the slot engine, on both the
  /// server and the mobile mock, with no constant and no test.
  final int minimumNoticeMinutes;

  const Availability({
    required this.providerId,
    required this.weeklySchedule,
    required this.blockedDates,
    this.bufferMinutes = 0,
    this.breaks = const {},
    this.bookingHorizonDays = kDefaultBookingHorizonDays,
    this.minimumNoticeMinutes = kDefaultMinimumNoticeMinutes,
  });

  @override
  List<Object?> get props => [
    providerId,
    weeklySchedule,
    blockedDates,
    bufferMinutes,
    breaks,
    bookingHorizonDays,
    minimumNoticeMinutes,
  ];

  Availability copyWith({
    String? providerId,
    Map<int, List<TimeSlot>>? weeklySchedule,
    List<DateTime>? blockedDates,
    int? bufferMinutes,
    Map<int, List<TimeSlot>>? breaks,
    int? bookingHorizonDays,
    int? minimumNoticeMinutes,
  }) {
    return Availability(
      providerId: providerId ?? this.providerId,
      weeklySchedule: weeklySchedule ?? this.weeklySchedule,
      blockedDates: blockedDates ?? this.blockedDates,
      bufferMinutes: bufferMinutes ?? this.bufferMinutes,
      breaks: breaks ?? this.breaks,
      bookingHorizonDays: bookingHorizonDays ?? this.bookingHorizonDays,
      minimumNoticeMinutes: minimumNoticeMinutes ?? this.minimumNoticeMinutes,
    );
  }

  static Map<String, dynamic> _scheduleToJson(Map<int, List<TimeSlot>> m) =>
      m.map(
        (key, value) => MapEntry(
          key.toString(),
          value.map((slot) => slot.toJson()).toList(),
        ),
      );

  static Map<int, List<TimeSlot>> _scheduleFromJson(Map? json) {
    if (json == null) return const {};
    return json.map(
      (key, value) => MapEntry(
        int.parse(key as String),
        (value as List)
            .map((slot) => TimeSlot.fromJson(slot as Map<String, dynamic>))
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'providerId': providerId,
      'weeklySchedule': _scheduleToJson(weeklySchedule),
      'blockedDates': blockedDates.map((d) => d.toIso8601String()).toList(),
      'bufferMinutes': bufferMinutes,
      'breaks': _scheduleToJson(breaks),
      // This map is an ALLOW-LIST, not a spread — a field on the class but not
      // here is erased on every write, and the pro app PUTs the whole object.
      // Gated by `expect(back, availability)`, which was watched red against
      // exactly this omission before the two lines below existed.
      'bookingHorizonDays': bookingHorizonDays,
      'minimumNoticeMinutes': minimumNoticeMinutes,
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
      // `as num?` + `??`, like bufferMinutes above: a payload from a server
      // that predates A14d must read the default, not throw.
      bookingHorizonDays:
          (json['bookingHorizonDays'] as num?)?.toInt() ??
          kDefaultBookingHorizonDays,
      minimumNoticeMinutes:
          (json['minimumNoticeMinutes'] as num?)?.toInt() ??
          kDefaultMinimumNoticeMinutes,
      breaks: _scheduleFromJson(json['breaks'] as Map?),
    );
  }
}
