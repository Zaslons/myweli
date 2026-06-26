import 'package:equatable/equatable.dart';

class Review extends Equatable {
  final String id;

  /// The completed appointment this review is of (one review per visit). May be
  /// empty for legacy/mock seed reviews.
  final String appointmentId;
  final String providerId;
  final String userId;
  final String userName;
  final int rating; // 1-5
  final String text;
  final bool verified; // true when tied to a completed booking
  final String? artistId;
  final String? artistName;

  /// The service(s) of the reviewed visit, for the feed card (e.g. "Coupe").
  final String serviceName;
  final List<String> photoUrls;
  final DateTime createdAt;

  const Review({
    required this.id,
    this.appointmentId = '',
    required this.providerId,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.text,
    this.verified = false,
    this.artistId,
    this.artistName,
    this.serviceName = '',
    this.photoUrls = const [],
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        appointmentId,
        providerId,
        userId,
        userName,
        rating,
        text,
        verified,
        artistId,
        artistName,
        serviceName,
        photoUrls,
        createdAt,
      ];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'appointmentId': appointmentId,
      'providerId': providerId,
      'userId': userId,
      'userName': userName,
      'rating': rating,
      'text': text,
      'verified': verified,
      'artistId': artistId,
      'artistName': artistName,
      'serviceName': serviceName,
      'photoUrls': photoUrls,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String,
      appointmentId: json['appointmentId'] as String? ?? '',
      providerId: json['providerId'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      rating: (json['rating'] as num).toInt(),
      text: json['text'] as String? ?? '',
      verified: json['verified'] as bool? ?? false,
      artistId: json['artistId'] as String?,
      artistName: json['artistName'] as String?,
      serviceName: json['serviceName'] as String? ?? '',
      photoUrls:
          (json['photoUrls'] as List?)?.map((e) => e as String).toList() ??
              const [],
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
