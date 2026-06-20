import 'package:equatable/equatable.dart';

class Artist extends Equatable {
  final String id;
  final String name;
  final String? imageUrl;
  final String providerId;
  final String? specialization; // e.g., 'Hair Stylist', 'Barber', 'Esthetician'
  final double? rating;
  final int? reviewCount;

  const Artist({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.providerId,
    this.specialization,
    this.rating,
    this.reviewCount,
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
      ];

  Artist copyWith({
    String? id,
    String? name,
    String? imageUrl,
    String? providerId,
    String? specialization,
    double? rating,
    int? reviewCount,
  }) {
    return Artist(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      providerId: providerId ?? this.providerId,
      specialization: specialization ?? this.specialization,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
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
    );
  }
}
