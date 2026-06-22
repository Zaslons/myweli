import 'package:equatable/equatable.dart';

import 'availability.dart';

class Artist extends Equatable {
  final String id;
  final String name;
  final String? imageUrl;
  final String providerId;
  final String? specialization; // e.g., 'Hair Stylist', 'Barber', 'Esthetician'
  final double? rating;
  final int? reviewCount;

  /// Per-staff weekly hours (0=Monday..6=Sunday). Empty = follows salon hours;
  /// a weekday absent/empty = day off for this member.
  final Map<int, List<TimeSlot>> workingHours;

  const Artist({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.providerId,
    this.specialization,
    this.rating,
    this.reviewCount,
    this.workingHours = const {},
  });

  @override
  List<Object?> get props => [
        id,
        name,
        imageUrl,
        providerId,
        specialization,
        rating,
        reviewCount,
        workingHours,
      ];

  Artist copyWith({
    String? id,
    String? name,
    String? imageUrl,
    String? providerId,
    String? specialization,
    double? rating,
    int? reviewCount,
    Map<int, List<TimeSlot>>? workingHours,
  }) {
    return Artist(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      providerId: providerId ?? this.providerId,
      specialization: specialization ?? this.specialization,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      workingHours: workingHours ?? this.workingHours,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imageUrl': imageUrl,
      'providerId': providerId,
      'specialization': specialization,
      'rating': rating,
      'reviewCount': reviewCount,
      'workingHours': workingHours.map(
        (key, value) => MapEntry(
          key.toString(),
          value.map((slot) => slot.toJson()).toList(),
        ),
      ),
    };
  }

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id'] as String,
      name: json['name'] as String,
      imageUrl: json['imageUrl'] as String?,
      providerId: json['providerId'] as String,
      specialization: json['specialization'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: json['reviewCount'] as int?,
      workingHours: (json['workingHours'] as Map?)?.map(
            (key, value) => MapEntry(
              int.parse(key as String),
              (value as List)
                  .map(
                      (slot) => TimeSlot.fromJson(slot as Map<String, dynamic>))
                  .toList(),
            ),
          ) ??
          const {},
    );
  }
}
