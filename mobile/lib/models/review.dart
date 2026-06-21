import 'package:equatable/equatable.dart';

class Review extends Equatable {
  final String id;
  final String providerId;
  final String userId;
  final String userName;
  final int rating; // 1-5
  final String text;
  final bool verified; // true when tied to a completed booking
  final String? artistId;
  final String? artistName;
  final List<String> photoUrls;
  final DateTime createdAt;

  const Review({
    required this.id,
    required this.providerId,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.text,
    this.verified = false,
    this.artistId,
    this.artistName,
    this.photoUrls = const [],
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        providerId,
        userId,
        userName,
        rating,
        text,
        verified,
        artistId,
        artistName,
        photoUrls,
        createdAt,
      ];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'providerId': providerId,
      'userId': userId,
      'userName': userName,
      'rating': rating,
      'text': text,
      'verified': verified,
      'artistId': artistId,
      'artistName': artistName,
      'photoUrls': photoUrls,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String,
      providerId: json['providerId'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      rating: json['rating'] as int,
      text: json['text'] as String,
      verified: json['verified'] as bool? ?? false,
      artistId: json['artistId'] as String?,
      artistName: json['artistName'] as String?,
      photoUrls:
          (json['photoUrls'] as List?)?.map((e) => e as String).toList() ??
              const [],
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
