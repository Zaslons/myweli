import 'package:equatable/equatable.dart';

import 'appointment.dart';

/// The salon's day as one payload (module `journal` J1 —
/// docs/design/journal-j1b-app.md). Mirrors the `JournalDay` DTO from
/// `GET /providers/{id}/journal?date=`.
class JournalDay extends Equatable {
  const JournalDay({
    required this.date,
    required this.artists,
    required this.appointments,
    this.hours,
  });

  /// 'YYYY-MM-DD' (UTC = Abidjan).
  final String date;

  /// Null when the salon is closed that day.
  final JournalHours? hours;
  final List<JournalArtist> artists;
  final List<Appointment> appointments;

  factory JournalDay.fromJson(Map<String, dynamic> json) => JournalDay(
        date: json['date'] as String,
        hours: json['hours'] == null
            ? null
            : JournalHours.fromJson(
                (json['hours'] as Map).cast<String, dynamic>(),
              ),
        artists: ((json['artists'] as List?) ?? const [])
            .map((e) =>
                JournalArtist.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        appointments: ((json['appointments'] as List?) ?? const [])
            .map(
                (e) => Appointment.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  @override
  List<Object?> get props => [date, hours, artists, appointments];
}

class JournalHours extends Equatable {
  const JournalHours({
    required this.open,
    required this.close,
    this.breaks = const [],
  });

  final String open; // 'HH:mm'
  final String close;
  final List<JournalBreak> breaks;

  factory JournalHours.fromJson(Map<String, dynamic> json) => JournalHours(
        open: json['open'] as String,
        close: json['close'] as String,
        breaks: ((json['breaks'] as List?) ?? const [])
            .map((e) =>
                JournalBreak.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  @override
  List<Object?> get props => [open, close, breaks];
}

class JournalBreak extends Equatable {
  const JournalBreak({required this.start, required this.end});

  final String start; // 'HH:mm'
  final String end;

  factory JournalBreak.fromJson(Map<String, dynamic> json) => JournalBreak(
        start: json['start'] as String,
        end: json['end'] as String,
      );

  @override
  List<Object?> get props => [start, end];
}

class JournalArtist extends Equatable {
  const JournalArtist({required this.id, required this.name, this.imageUrl});

  final String id;
  final String name;
  final String? imageUrl;

  factory JournalArtist.fromJson(Map<String, dynamic> json) => JournalArtist(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Artiste',
        imageUrl: json['imageUrl'] as String?,
      );

  @override
  List<Object?> get props => [id, name, imageUrl];
}
