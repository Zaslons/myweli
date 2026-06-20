import 'package:equatable/equatable.dart';

class Review extends Equatable {
  final String id;
  final String providerId;
  final String userId;
  final String userName;
  final int rating; // 1-5
  final String text;
  final DateTime createdAt;

  const Review({
    required this.id,
    required this.providerId,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.text,
    required this.createdAt,
  });

  @override
  List<Object?> get props =>
      [id, providerId, userId, userName, rating, text, createdAt];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'providerId': providerId,
      'userId': userId,
      'userName': userName,
      'rating': rating,
      'text': text,
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
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
