import 'package:equatable/equatable.dart';

/// Consumer account. Since the auth overhaul
/// (docs/design/auth-social-email.md) the identity is the verified email
/// (Google/Apple/email-OTP); [phoneNumber] is an optional CONTACT attribute,
/// unverified until proven via SMS later ([phoneVerified]).
class User extends Equatable {
  final String id;
  final String? phoneNumber;
  final bool phoneVerified;
  final String? name;
  final String? email;
  final String? authProvider; // google | apple | email | phone
  final String? avatarUrl;
  final DateTime createdAt;

  const User({
    required this.id,
    this.phoneNumber,
    this.phoneVerified = false,
    this.name,
    this.email,
    this.authProvider,
    this.avatarUrl,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        phoneNumber,
        phoneVerified,
        name,
        email,
        authProvider,
        avatarUrl,
        createdAt,
      ];

  User copyWith({
    String? id,
    String? phoneNumber,
    bool? phoneVerified,
    String? name,
    String? email,
    String? authProvider,
    String? avatarUrl,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      name: name ?? this.name,
      email: email ?? this.email,
      authProvider: authProvider ?? this.authProvider,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'phoneVerified': phoneVerified,
      'name': name,
      'email': email,
      'authProvider': authProvider,
      'avatarUrl': avatarUrl,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      phoneNumber: json['phoneNumber'] as String?,
      phoneVerified: json['phoneVerified'] as bool? ?? false,
      name: json['name'] as String?,
      email: json['email'] as String?,
      authProvider: json['authProvider'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
