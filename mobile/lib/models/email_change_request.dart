import 'package:equatable/equatable.dart';

/// What `POST /me/email/otp/request` answered (202): the first step of an
/// address change (docs/design/account-email-change.md §3.1, §5.4).
///
/// [currentCodeSent]: a second code went to the account's current address,
/// because that proven address is its only way in (decision 265) — the code
/// step then asks for both. [devCode] and [currentDevCode] come from a dev
/// backend only, never production.
class EmailChangeRequest extends Equatable {
  final int expiresInSeconds;
  final bool currentCodeSent;
  final String? devCode;
  final String? currentDevCode;

  const EmailChangeRequest({
    required this.expiresInSeconds,
    required this.currentCodeSent,
    this.devCode,
    this.currentDevCode,
  });

  factory EmailChangeRequest.fromJson(Map<String, dynamic> json) =>
      EmailChangeRequest(
        expiresInSeconds: json['expiresInSeconds'] as int,
        currentCodeSent: json['currentCodeSent'] as bool,
        devCode: json['devCode'] as String?,
        currentDevCode: json['currentDevCode'] as String?,
      );

  @override
  List<Object?> get props => [
    expiresInSeconds,
    currentCodeSent,
    devCode,
    currentDevCode,
  ];
}
