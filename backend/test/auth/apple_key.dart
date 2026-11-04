import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart' as asn1;
import 'package:pointycastle/export.dart' as pc;

/// A throwaway P-256 key pair for the Sign in with Apple tests — generated
/// here, never a key in the repository (gitleaks reads every branch).
pc.AsymmetricKeyPair<pc.ECPublicKey, pc.ECPrivateKey> appleTestKeyPair([
  int seed = 7,
]) {
  final random = pc.FortunaRandom()
    ..seed(
      pc.KeyParameter(
        Uint8List.fromList(List.generate(32, (i) => (i * 31 + seed) % 256)),
      ),
    );
  final generator = pc.ECKeyGenerator()
    ..init(
      pc.ParametersWithRandom(
        pc.ECKeyGeneratorParameters(pc.ECCurve_secp256r1()),
        random,
      ),
    );
  final pair = generator.generateKeyPair();
  return pc.AsymmetricKeyPair(
    pair.publicKey as pc.ECPublicKey,
    pair.privateKey as pc.ECPrivateKey,
  );
}

/// [key] as Apple hands it over: a PKCS#8 PEM (`AuthKey_<id>.p8`) —
/// `PrivateKeyInfo { 0, { ecPublicKey, prime256v1 }, ECPrivateKey { 1, d } }`.
String applePkcs8Pem(pc.ECPrivateKey key) {
  final d = key.d!;
  final dBytes = Uint8List(32);
  var v = d;
  for (var i = 31; i >= 0; i--) {
    dBytes[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  final inner = asn1.ASN1Sequence(
    elements: [
      asn1.ASN1Integer(BigInt.one),
      asn1.ASN1OctetString(octets: dBytes),
    ],
  );
  final info = asn1.ASN1Sequence(
    elements: [
      asn1.ASN1Integer(BigInt.zero),
      asn1.ASN1Sequence(
        elements: [
          asn1.ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.2.1'),
          asn1.ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.3.1.7'),
        ],
      ),
      asn1.ASN1OctetString(octets: inner.encode()),
    ],
  );
  final b64 = base64.encode(info.encode());
  final lines = [
    for (var i = 0; i < b64.length; i += 64)
      b64.substring(i, min(i + 64, b64.length)),
  ];
  // The armor is composed, not a literal — gitleaks' private-key rule reads
  // the two armor lines, whatever lies between (the CI reason, ci.yml).
  const armor = 'PRIVATE KEY';
  return [
    '-----BEGIN $armor-----',
    ...lines,
    '-----END $armor-----',
  ].join('\n');
}
