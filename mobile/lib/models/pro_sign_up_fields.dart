import 'provider_user.dart';

/// What the Android sign-up sends about the salon
/// (docs/design/pro-android-signup.md §2.4, §3): the body of
/// `POST /auth/provider/register` without its identity.
///
/// The server is the authority on every field (§6.4); the app checks them
/// first only to put each fault under its field. [phoneNumber] is E.164, as
/// `PhoneNumberField` emits it. [address] is required in the app (R2), and
/// [areaId] is the commune picker's optional choice.
class ProSignUpFields {
  const ProSignUpFields({
    required this.businessName,
    required this.businessType,
    required this.phoneNumber,
    required this.address,
    this.areaId,
  });

  final String businessName;
  final BusinessType businessType;
  final String phoneNumber;
  final String address;
  final String? areaId;

  /// The register body's salon half. `areaId` is omitted when none was
  /// chosen: the server stamps the default market then (§4).
  Map<String, String> toJson() => {
    'businessName': businessName,
    'businessType': businessType.name,
    'phoneNumber': phoneNumber,
    'address': address,
    'areaId': ?areaId,
  };
}
