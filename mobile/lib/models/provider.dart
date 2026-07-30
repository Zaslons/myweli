import 'package:equatable/equatable.dart';

import 'artist.dart';
import 'availability.dart';
import 'before_after_pair.dart';
import 'review.dart';
import 'service.dart';

class Provider extends Equatable {
  final String id;
  final String name;
  final String description;
  final String address;
  final String? city;
  final String? commune;

  /// Multi-pays MP2 (multi-pays-end-version.md §2): the salon's locality
  /// (an Area id from GET /localities) + the market facts DERIVED from it
  /// server-side — never client-written (threat T57).
  final String? areaId;
  final String? citySlug;
  final String? countryCode; // ISO-3166 alpha-2
  final String? timezone; // IANA — feeds every salon-time helper
  final String? currency; // ISO-4217 — feeds every money formatter
  final double? latitude;
  final double? longitude;
  final List<String> imageUrls;
  final List<BeforeAfterPair> beforeAfters;
  final String? logoUrl;
  final double rating;
  final int reviewCount;
  final List<Service> services;
  final List<Artist> artists;
  final Availability availability;
  final String phoneNumber;
  final String? whatsapp;
  final String category; // 'salon', 'barber', 'spa', etc.

  /// Server-owned « Vérifié » badge (KYC approved — T52).
  final bool verified;
  final bool depositRequired;
  final double depositPercentage;

  /// Mobile Money handle the deposit is sent to (the deposit is paid directly
  /// client→salon — Myweli holds nothing). Null until the salon configures
  /// it. The value is an operator id from the salon COUNTRY's catalog
  /// (GET /localities — multi-pays MP2; labels/deep links render from the
  /// catalog, never from a client enum).
  final String? depositMobileMoneyOperator;
  final String? depositMobileMoneyNumber;

  /// Hours before the appointment within which a cancellation forfeits the
  /// deposit. Per-salon policy; defaults to 24h.
  final int cancellationWindowHours;
  final List<Review> reviews;

  const Provider({
    required this.id,
    required this.name,
    required this.description,
    required this.address,
    this.city,
    this.commune,
    this.areaId,
    this.citySlug,
    this.countryCode,
    this.timezone,
    this.currency,
    this.latitude,
    this.longitude,
    required this.imageUrls,
    this.beforeAfters = const [],
    this.logoUrl,
    required this.rating,
    required this.reviewCount,
    required this.services,
    this.artists = const [],
    required this.availability,
    required this.phoneNumber,
    this.whatsapp,
    required this.category,
    this.verified = false,
    this.depositRequired = false,
    this.depositPercentage = 0.30,
    this.depositMobileMoneyOperator,
    this.depositMobileMoneyNumber,
    this.cancellationWindowHours = 24,
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
        areaId,
        citySlug,
        countryCode,
        timezone,
        currency,
        latitude,
        longitude,
        imageUrls,
        beforeAfters,
        logoUrl,
        rating,
        reviewCount,
        services,
        artists,
        availability,
        phoneNumber,
        whatsapp,
        category,
        verified,
        depositRequired,
        depositPercentage,
        depositMobileMoneyOperator,
        depositMobileMoneyNumber,
        cancellationWindowHours,
        reviews,
      ];

  Provider copyWith({
    String? id,
    String? name,
    String? description,
    String? address,
    String? city,
    String? commune,
    String? areaId,
    String? citySlug,
    String? countryCode,
    String? timezone,
    String? currency,
    double? latitude,
    double? longitude,
    List<String>? imageUrls,
    List<BeforeAfterPair>? beforeAfters,
    String? logoUrl,
    double? rating,
    int? reviewCount,
    List<Service>? services,
    List<Artist>? artists,
    Availability? availability,
    String? phoneNumber,
    String? whatsapp,
    String? category,
    bool? verified,
    bool? depositRequired,
    double? depositPercentage,
    String? depositMobileMoneyOperator,
    String? depositMobileMoneyNumber,
    int? cancellationWindowHours,
    List<Review>? reviews,
  }) {
    return Provider(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      address: address ?? this.address,
      city: city ?? this.city,
      commune: commune ?? this.commune,
      areaId: areaId ?? this.areaId,
      citySlug: citySlug ?? this.citySlug,
      countryCode: countryCode ?? this.countryCode,
      timezone: timezone ?? this.timezone,
      currency: currency ?? this.currency,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      imageUrls: imageUrls ?? this.imageUrls,
      beforeAfters: beforeAfters ?? this.beforeAfters,
      logoUrl: logoUrl ?? this.logoUrl,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      services: services ?? this.services,
      artists: artists ?? this.artists,
      availability: availability ?? this.availability,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      whatsapp: whatsapp ?? this.whatsapp,
      category: category ?? this.category,
      verified: verified ?? this.verified,
      depositRequired: depositRequired ?? this.depositRequired,
      depositPercentage: depositPercentage ?? this.depositPercentage,
      depositMobileMoneyOperator:
          depositMobileMoneyOperator ?? this.depositMobileMoneyOperator,
      depositMobileMoneyNumber:
          depositMobileMoneyNumber ?? this.depositMobileMoneyNumber,
      cancellationWindowHours:
          cancellationWindowHours ?? this.cancellationWindowHours,
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
      'areaId': areaId,
      'citySlug': citySlug,
      'countryCode': countryCode,
      'timezone': timezone,
      'currency': currency,
      'latitude': latitude,
      'longitude': longitude,
      'imageUrls': imageUrls,
      'beforeAfters': beforeAfters.map((p) => p.toJson()).toList(),
      'logoUrl': logoUrl,
      'rating': rating,
      'reviewCount': reviewCount,
      'services': services.map((s) => s.toJson()).toList(),
      'artists': artists.map((a) => a.toJson()).toList(),
      'availability': availability.toJson(),
      'phoneNumber': phoneNumber,
      'whatsapp': whatsapp,
      'category': category,
      'verified': verified,
      'depositRequired': depositRequired,
      'depositPercentage': depositPercentage,
      'depositMobileMoneyOperator': depositMobileMoneyOperator,
      'depositMobileMoneyNumber': depositMobileMoneyNumber,
      'cancellationWindowHours': cancellationWindowHours,
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
      areaId: json['areaId'] as String?,
      citySlug: json['citySlug'] as String?,
      countryCode: json['countryCode'] as String?,
      timezone: json['timezone'] as String?,
      currency: json['currency'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      imageUrls: List<String>.from(json['imageUrls'] as List),
      beforeAfters: ((json['beforeAfters'] as List?) ?? const [])
          .map((p) => BeforeAfterPair.fromJson(p as Map<String, dynamic>))
          .toList(),
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
      whatsapp: json['whatsapp'] as String?,
      category: json['category'] as String,
      verified: json['verified'] as bool? ?? false,
      depositRequired: json['depositRequired'] as bool? ?? false,
      depositPercentage:
          (json['depositPercentage'] as num?)?.toDouble() ?? 0.30,
      depositMobileMoneyOperator: json['depositMobileMoneyOperator'] as String?,
      depositMobileMoneyNumber: json['depositMobileMoneyNumber'] as String?,
      cancellationWindowHours: json['cancellationWindowHours'] as int? ?? 24,
      reviews: json['reviews'] != null
          ? (json['reviews'] as List)
              .map((r) => Review.fromJson(r as Map<String, dynamic>))
              .toList()
          : [],
    );
  }
}
