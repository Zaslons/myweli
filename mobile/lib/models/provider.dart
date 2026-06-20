import 'package:equatable/equatable.dart';

import 'artist.dart';
import 'availability.dart';
import 'review.dart';
import 'service.dart';

class Provider extends Equatable {
  final String id;
  final String name;
  final String description;
  final String address;
  final String? city;
  final String? commune;
  final double? latitude;
  final double? longitude;
  final List<String> imageUrls;
  final String? logoUrl;
  final double rating;
  final int reviewCount;
  final List<Service> services;
  final List<Artist> artists;
  final Availability availability;
  final String phoneNumber;
  final String category; // 'salon', 'barber', 'spa', etc.
  final bool depositRequired;
  final double depositPercentage;
  final List<Review> reviews;

  const Provider({
    required this.id,
    required this.name,
    required this.description,
    required this.address,
    this.city,
    this.commune,
    this.latitude,
    this.longitude,
    required this.imageUrls,
    this.logoUrl,
    required this.rating,
    required this.reviewCount,
    required this.services,
    this.artists = const [],
    required this.availability,
    required this.phoneNumber,
    required this.category,
    this.depositRequired = true,
    this.depositPercentage = 0.30,
    this.reviews = const [],
  });

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        address,
        city,
        commune,
        latitude,
        longitude,
        imageUrls,
        logoUrl,
        rating,
        reviewCount,
        services,
        artists,
        availability,
        phoneNumber,
        category,
        depositRequired,
        depositPercentage,
        reviews,
      ];

  Provider copyWith({
    String? id,
    String? name,
    String? description,
    String? address,
    String? city,
    String? commune,
    double? latitude,
    double? longitude,
    List<String>? imageUrls,
    String? logoUrl,
    double? rating,
    int? reviewCount,
    List<Service>? services,
    List<Artist>? artists,
    Availability? availability,
    String? phoneNumber,
    String? category,
    bool? depositRequired,
    double? depositPercentage,
    List<Review>? reviews,
  }) {
    return Provider(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      address: address ?? this.address,
      city: city ?? this.city,
      commune: commune ?? this.commune,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      imageUrls: imageUrls ?? this.imageUrls,
      logoUrl: logoUrl ?? this.logoUrl,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      services: services ?? this.services,
      artists: artists ?? this.artists,
      availability: availability ?? this.availability,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      category: category ?? this.category,
      depositRequired: depositRequired ?? this.depositRequired,
      depositPercentage: depositPercentage ?? this.depositPercentage,
      reviews: reviews ?? this.reviews,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'address': address,
      'city': city,
      'commune': commune,
      'latitude': latitude,
      'longitude': longitude,
      'imageUrls': imageUrls,
      'logoUrl': logoUrl,
      'rating': rating,
      'reviewCount': reviewCount,
      'services': services.map((s) => s.toJson()).toList(),
      'artists': artists.map((a) => a.toJson()).toList(),
      'availability': availability.toJson(),
      'phoneNumber': phoneNumber,
      'category': category,
      'depositRequired': depositRequired,
      'depositPercentage': depositPercentage,
      'reviews': reviews.map((r) => r.toJson()).toList(),
    };
  }

  factory Provider.fromJson(Map<String, dynamic> json) {
    return Provider(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      address: json['address'] as String,
      city: json['city'] as String?,
      commune: json['commune'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      imageUrls: List<String>.from(json['imageUrls'] as List),
      logoUrl: json['logoUrl'] as String?,
      rating: (json['rating'] as num).toDouble(),
      reviewCount: json['reviewCount'] as int,
      services: (json['services'] as List)
          .map((s) => Service.fromJson(s as Map<String, dynamic>))
          .toList(),
      artists: json['artists'] != null
          ? (json['artists'] as List)
              .map((a) => Artist.fromJson(a as Map<String, dynamic>))
              .toList()
          : [],
      availability:
          Availability.fromJson(json['availability'] as Map<String, dynamic>),
      phoneNumber: json['phoneNumber'] as String,
      category: json['category'] as String,
      depositRequired: json['depositRequired'] as bool? ?? true,
      depositPercentage:
          (json['depositPercentage'] as num?)?.toDouble() ?? 0.30,
      reviews: json['reviews'] != null
          ? (json['reviews'] as List)
              .map((r) => Review.fromJson(r as Map<String, dynamic>))
              .toList()
          : [],
    );
  }
}
