import 'dart:io';

import 'package:myweli_backend/src/auth/apple_key_probe.dart';
import 'package:myweli_backend/src/auth/apple_tokens.dart';

/// Asks Apple whether a Sign in with Apple key covers each client — before
/// the key is deployed (docs/design/apple-signin-keys.md §5, §9 step 2).
///
/// ```sh
/// dart run tool/apple_key_probe.dart <TEAM_ID> <KEY_ID> <path/AuthKey.p8> \
///   com.myweli.app com.myweli.pro com.myweli.signin
/// ```
///
/// Run each key against ALL the clients: its own must say COVERED, and the
/// other app's must say NOT COVERED — that second answer is the control. If
/// every client says COVERED, the probe did not discriminate; say so rather
/// than trusting it. Prints the client, the verdict and Apple's error word;
/// never the key, the client secret or a token. Exits 1 if any answer is
/// UNKNOWN.
Future<void> main(List<String> args) async {
  if (args.length < 4) {
    stderr.writeln(
      'usage: dart run tool/apple_key_probe.dart <TEAM_ID> <KEY_ID> '
      '<path/AuthKey.p8> <client> [<client>…]',
    );
    exitCode = 64;
    return;
  }
  final key = AppleSignInKey.fromPem(
    teamId: args[0],
    keyId: args[1],
    pem: File(args[2]).readAsStringSync(),
    name: args[2],
  );
  var unknown = false;
  for (final clientId in args.skip(3)) {
    final p = await probeAppleKey(key, clientId);
    if (p.coverage == AppleKeyCoverage.unknown) unknown = true;
    stdout.writeln('key ${args[1]} → ${describeAppleKeyProbe(p)}');
  }
  if (unknown) exitCode = 1;
}
