import 'package:equatable/equatable.dart';

/// Consumer account. Since the auth overhaul
/// (docs/design/auth-social-email.md) the identity is the verified email
/// (Google/Apple/email-OTP); [phoneNumber] is an optional CONTACT attribute,
/// unverified until proven via SMS later ([phoneVerified]).
///
/// [emailVerified]: the account proved [email] — by a code sent to it, or by
/// Google or Apple asserting it. Only a proven address signs the account in,
/// and it changes only by a code (docs/design/account-email-change.md §3.3,
/// §5.4; decisions 260, 261).
class User extends Equatable {
  final String id;
  final String? phoneNumber;
  final bool phoneVerified;
  final String? name;
  final String? email;
  final bool emailVerified;
  final String? authProvider; // google | apple | email | phone
  final String? avatarUrl;
  final DateTime createdAt;

  const User({
    required this.id,
    this.phoneNumber,
    this.phoneVerified = false,
    this.name,
    this.email,
    this.emailVerified = false,
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
    emailVerified,
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
    bool? emailVerified,
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
      emailVerified: emailVerified ?? this.emailVerified,
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
      'emailVerified': emailVerified,
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
      // Absent only in a session stored by a build before B16.3b: the server
      // sends it on every `User` since B16.3a. Every address in production was
      // proven at both of §9.1's reads, and no route writes an unproven one
      // since, so an address there is a proven one — read as unproven, the
      // profile would say « Non vérifiée » to everyone who updates.
      emailVerified: json['emailVerified'] as bool? ?? json['email'] != null,
      authProvider: json['authProvider'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
