import 'dart:io';

import 'package:test/test.dart';

/// The two scripts that retire and verify the Cloudflare front door
/// (docs/design/infra-cloudflare-front-door.md §5.5 and §8).
///
/// `71-retire-load-balancer.sh` deletes the load balancer, its address and
/// certificate, the Cloud Armor policy and the alert that watched it. The
/// properties worth pinning are the ones that make a deletion script safe to
/// have in a repository: it cannot run by accident, it deletes in an order the
/// API will accept, and it can never quietly grow a provisioning line — the
/// word `create` is forbidden ANYWHERE in the file, comments included, because
/// a commented-out call is a line someone uncomments at 2am (the
/// `r2_manifest_test` verb rule; `secret_pins_test` records why comments are
/// deliberately not stripped for this kind of guard).
///
/// `72-verify-front-door.sh` is the read-only acceptance of the live path. Its
/// header promises read-only; this is what makes that a property rather than a
/// comment — with one named exception, the forced cron run §9 step 8 requires,
/// which must sit behind `RUN_CRON=1` and nowhere else.
///
/// Pins about the manifest live in `service_files_test.dart`; pins about the
/// Worker and the Dart middleware live next to those files.
void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  String read(String name) => File('$root/infra/gcp/$name').readAsStringSync();

  /// Shell comments stripped — used only where PRESENCE of code is asserted,
  /// so a comment cannot satisfy a guard (`ci_secret_scan_test` idiom).
  String code(String sh) =>
      sh.split('\n').where((l) => !l.trimLeft().startsWith('#')).join('\n');

  group('71-retire-load-balancer.sh', () {
    final retire = read('71-retire-load-balancer.sh');
    final retireCode = code(retire);

    test('refuses unless CONFIRM=retire', () {
      // The guard is in code, not prose: a header that says "requires
      // CONFIRM" while the script runs regardless is the failure this catches.
      expect(retireCode, contains('CONFIRM'));
      expect(
        RegExp(r'CONFIRM[^\n]*!=[^\n]*"retire"').hasMatch(retireCode),
        isTrue,
        reason:
            'the script must compare CONFIRM against the literal "retire" '
            'and refuse on a mismatch',
      );
      expect(retireCode, contains('exit 1'));
    });

    test('never contains the word `create` — anywhere, comments included', () {
      // Lower-cased so `Create`/`CREATE` cannot slip past. A retire script
      // that can provision is a script that undoes itself on a re-run.
      expect(
        retire.toLowerCase(),
        isNot(contains('create')),
        reason:
            '71-retire-load-balancer.sh contains "create". Comments count: '
            'this is the one guard where a commented-out call is the hazard '
            'rather than noise',
      );
    });

    test('reads before it deletes — every resource is described first', () {
      // The PITR-purge lesson: print the live state, then decide. The first
      // `describe` must come before the first `delete`.
      final firstDescribe = retireCode.indexOf(' describe ');
      final firstDelete = retireCode.indexOf(' delete ');
      expect(firstDescribe, greaterThanOrEqualTo(0));
      expect(firstDelete, greaterThanOrEqualTo(0));
      expect(firstDescribe, lessThan(firstDelete));
    });

    test('requires the three observations before deleting anything', () {
      // Each would be false if the cutover were incomplete. They are asserted
      // by their observable strings, and all three must precede the first
      // delete.
      final firstDelete = retireCode.indexOf(' delete ');
      for (final marker in [
        'dig +short',
        '8.232.126.191',
        'cf-ray',
        'origin_required',
      ]) {
        final at = retireCode.indexOf(marker);
        expect(at, greaterThanOrEqualTo(0), reason: 'missing: $marker');
        expect(
          at,
          lessThan(firstDelete),
          reason: '$marker is checked only after a delete has already run',
        );
      }
    });

    test('deletes in reverse-reference order', () {
      // The order the API accepts: nothing can be deleted while something
      // else still references it. Index of first occurrence, ascending.
      const order = [
        'forwarding-rules delete',
        'target-https-proxies delete',
        'url-maps delete',
        'backend-services delete',
        'network-endpoint-groups delete',
        'ssl-certificates delete',
        'addresses delete',
        'security-policies delete',
      ];
      var last = -1;
      for (final verb in order) {
        final at = retireCode.indexOf(verb);
        expect(at, greaterThanOrEqualTo(0), reason: 'missing: $verb');
        expect(
          at,
          greaterThan(last),
          reason: '$verb appears before the resource that references it',
        );
        last = at;
      }
      // Detach before the backend goes, or the policy delete is refused.
      expect(
        retireCode.indexOf('--security-policy=""'),
        lessThan(retireCode.indexOf('backend-services delete')),
      );
      // The NEG is regional; a global delete would simply not find it.
      expect(retireCode, contains('network-endpoint-groups delete'));
      expect(retireCode, contains(r'--region="${REGION}"'));
      expect(retireCode, contains('REGION=europe-west9'));
    });

    test(
      'the alert goes by displayName; the shared channel is never touched',
      () {
        expect(retireCode, contains('Cloud Armor REFUSED a request'));
        expect(retireCode, contains('monitoring policies list'));
        expect(retireCode, contains('monitoring policies delete'));
        expect(
          retire,
          isNot(contains('channels delete')),
          reason:
              'the "Owner email" channel is shared by every other alert; '
              'deleting it would silence all of them',
        );
      },
    );

    test('ends by naming the two follow-ups it cannot do itself', () {
      expect(retire, contains('192.0.2.0'));
      expect(retire, contains('Forwarding Rule Minimum Global'));
    });
  });

  group('72-verify-front-door.sh', () {
    final verify = read('72-verify-front-door.sh');
    final verifyCode = code(verify);

    test('it names no mutating gcloud verb (comments included)', () {
      // gcloud's ACTUAL subcommand paths, matched anywhere in the file.
      // `scheduler jobs run` is the one exception and has its own test.
      const mutating = [
        'run services replace',
        'run services update',
        'run services delete',
        'run deploy',
        'secrets versions add',
        'secrets versions access',
        'secrets versions disable',
        'secrets versions destroy',
        'secrets create',
        'secrets delete',
        'scheduler jobs create',
        'scheduler jobs update',
        'scheduler jobs delete',
        'scheduler jobs pause',
        'scheduler jobs resume',
        'monitoring policies create',
        'monitoring policies update',
        'monitoring policies delete',
        'monitoring uptime create',
        'monitoring uptime update',
        'monitoring uptime delete',
        'monitoring channels create',
        'monitoring channels delete',
        'compute forwarding-rules delete',
        'compute backend-services update',
        'compute security-policies',
        'add-iam-policy-binding',
        'wrangler deploy',
        'wrangler secret',
      ];
      for (final verb in mutating) {
        expect(
          verify,
          isNot(contains(verb)),
          reason:
              '72-verify-front-door.sh mentions `$verb`. It is the acceptance '
              'script pointed at PRODUCTION on the strength of being unable '
              'to change anything.',
        );
      }
    });

    test('curl never sends a mutating method', () {
      // POST is allowed: the OTP request route exists to be probed (the
      // 87/89 burst). Anything that could change a resource is not.
      expect(RegExp(r'-X\s+(PUT|PATCH|DELETE)').hasMatch(verify), isFalse);
    });

    test(
      'the one mutating call, `scheduler jobs run`, sits behind RUN_CRON',
      () {
        final lines = verifyCode.split('\n');
        final hits = <int>[];
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('scheduler jobs run')) hits.add(i);
        }
        expect(hits, hasLength(1), reason: 'exactly one forced run');

        // Walk back from the line BEFORE the call (the call itself is an `if`)
        // to the nearest enclosing `if`, which must be the RUN_CRON gate — with
        // no `fi` closing it in between.
        var i = hits.single - 1;
        var guarded = false;
        var depth = 0;
        while (i >= 0) {
          final l = lines[i].trim();
          if (l == 'fi') depth++;
          if (l.startsWith('if ')) {
            if (depth == 0) {
              guarded = l.contains('RUN_CRON');
              break;
            }
            depth--;
          }
          i--;
        }
        expect(
          guarded,
          isTrue,
          reason:
              'the forced cron run is not inside `if [[ "\${RUN_CRON:-0}" == '
              '"1" ]]` — running the script would dispatch a reminder',
        );
        expect(verifyCode, contains('RUN_CRON:-0'), reason: 'default off');
      },
    );

    test('it checks what §8 lists', () {
      for (final s in [
        '/auth/email/otp/request',
        'rate_limited',
        '/health',
        'origin_required',
        'myweli-api-5a24ymhbbq-od.a.run.app',
        'myweli-api-731308991240.europe-west9.run.app',
        'cf-ray',
        'uptime list-configs',
        'uptime_check/check_passed',
        'https://admin.myweli.com',
        'Access-Control-Request-Method: GET',
        'access-control-allow-origin',
        'Dart/3.5 (dart:io)',
        'myweli-reminders',
      ]) {
        expect(verifyCode, contains(s), reason: 'missing: $s');
      }
    });

    test('the burst wants ≥1 non-429 AND 429s with a JSON body', () {
      // Every-429 proves nothing about the route; a 429 without the envelope
      // is the edge (HTML), not the app's authoritative limit.
      expect(verifyCode, contains('seq 1 15'));
      expect(verifyCode, contains('NON429 < 1'));
      expect(verifyCode, contains('"rate_limited"'));
    });

    test('it fails loudly, and refuses to report success having checked '
        'nothing', () {
      expect(verify, contains('set -uo pipefail'));
      expect(verify, contains('exit 1'));
      expect(
        RegExp(r'COUNT.*-lt\s+\d+').hasMatch(verifyCode),
        isTrue,
        reason: 'the vacuity floor is gone',
      );
      expect(verifyCode, contains('Refusing to report success'));
    });
  });
}
