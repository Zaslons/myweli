import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The invariants that span `infra/gcp/service.yaml` and
/// `infra/gcp/service-staging.yaml` (docs/design/infra-staging.md).
///
/// **Why a test rather than a review checklist.** These two files are 90%
/// identical by design — a staging environment that differs where it did not
/// have to is rehearsing something else — which is exactly the condition under
/// which a copy-paste edit misses one line. Every assertion below is a
/// same-value-in-two-files relationship that no single file's review can catch,
/// and several of them fail in the dangerous direction: a staging service that
/// runs migrations against the production database, or mounts a production
/// secret, does not look broken. It looks fine.
///
/// The files are read from disk rather than fixtured, so this fails when the
/// real deployed configuration drifts, not when a copy of it does.
void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  YamlMap load(String name) =>
      loadYaml(File('$root/infra/gcp/$name').readAsStringSync()) as YamlMap;

  final files = {
    'prod': load('service.yaml'),
    'staging': load('service-staging.yaml'),
  };

  YamlMap podSpec(YamlMap svc) => svc['spec']['template']['spec'] as YamlMap;
  YamlMap templateAnnotations(YamlMap svc) =>
      svc['spec']['template']['metadata']['annotations'] as YamlMap;
  YamlList appEnv(YamlMap svc) =>
      podSpec(svc)['containers'][0]['env'] as YamlList;

  String? plainEnv(YamlMap svc, String name) {
    for (final e in appEnv(svc)) {
      if (e['name'] == name) return e['value'] as String?;
    }
    return null;
  }

  Set<String> secretNames(YamlMap svc) => {
    for (final e in appEnv(svc))
      if (e['valueFrom'] != null)
        e['valueFrom']['secretKeyRef']['name'] as String,
  };

  /// The Cloud SQL instance, as named in the annotation.
  String sqlAnnotation(YamlMap svc) =>
      templateAnnotations(svc)['run.googleapis.com/cloudsql-instances']
          as String;

  /// The Cloud SQL instance, as named in the proxy sidecar's argv — the second,
  /// far-away copy of the same string.
  String sqlProxyArg(YamlMap svc) {
    final proxy = (podSpec(svc)['containers'] as YamlList).firstWhere(
      (c) => c['name'] == 'cloudsql-proxy',
    );
    return (proxy['args'] as YamlList).last as String;
  }

  group('the two-place database hazard', () {
    // `DATABASE_URL` points at 127.0.0.1:5432, so the connection string carries
    // NO information about which database it reaches. The instance identity
    // lives only in these two strings, ~180 lines apart with the whole env block
    // between them. Edit one and miss the other and the service either cannot
    // connect at all — or, in the direction that matters, runs migrations and
    // three backfills against the wrong database.
    for (final entry in files.entries) {
      test('${entry.key}: the annotation and the proxy arg name ONE instance', () {
        expect(
          sqlProxyArg(entry.value),
          sqlAnnotation(entry.value),
          reason:
              'the cloudsql-instances annotation and the proxy sidecar argument '
              'must be byte-identical; they are the only two places the database '
              'is named, and nothing else would notice they disagree',
        );
      });
    }

    test('staging and production do NOT share a database instance', () {
      expect(
        sqlAnnotation(files['staging']!),
        isNot(sqlAnnotation(files['prod']!)),
        reason: 'the whole premise: same shape, never the same data',
      );
      expect(sqlAnnotation(files['staging']!), endsWith('-staging'));
    });
  });

  group('identity — which service a file deploys', () {
    // `gcloud run services replace` takes the service name from metadata.name
    // INSIDE the file; there is no positional argument. The file path is
    // therefore the only thing that decides which service a deploy lands on,
    // which is why the name is a literal in both files and never templated —
    // and why deploy-backend.yml asserts it against the environment.
    test('each file declares its own distinct service', () {
      final prod = files['prod']!['metadata']['name'] as String;
      final staging = files['staging']!['metadata']['name'] as String;
      expect(prod, 'myweli-api');
      expect(staging, 'myweli-api-staging');
      expect(staging, isNot(prod));
    });

    test('neither name is a substitution placeholder', () {
      for (final entry in files.entries) {
        expect(
          entry.value['metadata']['name'] as String,
          isNot(contains('__')),
          reason:
              '${entry.key}: templating the service name would mean the service '
              'identity is invented at deploy time by a shell substitution',
        );
      }
    });

    test('ENV matches the file it is in', () {
      expect(plainEnv(files['prod']!, 'ENV'), 'prod');
      expect(plainEnv(files['staging']!, 'ENV'), 'staging');
    });

    test('the runtime service accounts are separate', () {
      // Sharing `myweli-run@` would make the secret split below cosmetic: that
      // account holds secretAccessor on every PRODUCTION secret version, so a
      // staging manifest naming `DATABASE_URL` instead of `STAGING_DATABASE_URL`
      // would simply work, and the isolation would rest on nobody mistyping.
      expect(
        podSpec(files['staging']!)['serviceAccountName'],
        isNot(podSpec(files['prod']!)['serviceAccountName']),
      );
    });
  });

  group('secrets — what staging may and may not reach', () {
    /// Shared deliberately, each for a reason that does not apply to the rest.
    /// Anything else appearing in both files is a production credential
    /// mounted into a publicly-reachable environment that echoes OTP codes.
    const deliberatelyShared = {
      // Write-only ingestion key; events carry `environment` from the same
      // `Env` the guards use, so one project is correct and two would split
      // release health for one codebase.
      'SENTRY_DSN',
      // Public OAuth client identifiers — they ship inside the app binary.
      // They are an audience allowlist, so different values would mean staging
      // accepts tokens production rejects.
      'GOOGLE_CLIENT_IDS',
      'APPLE_CLIENT_IDS',
      // The Cloudflare account id. A twin would be byte-identical, and two
      // copies of one value is drift waiting to happen. The R2 *credential* is
      // separate and bucket-scoped.
      'R2_ACCOUNT_ID',
    };

    test('no production secret is mounted into staging by accident', () {
      final shared = secretNames(
        files['prod']!,
      ).intersection(secretNames(files['staging']!));
      expect(
        shared,
        deliberatelyShared,
        reason:
            'every secret in both files must be a deliberate exception with a '
            'stated reason. A new name here means staging can read a production '
            'credential — and JWT_SECRET especially, because a token minted in '
            'staging (where we hand out admin credentials) would then '
            'authenticate against production.',
      );
    });

    test('JWT_SECRET and DATABASE_URL are never shared, stated separately', () {
      // The two that would be catastrophic rather than merely wrong, asserted
      // by name so the test above cannot be "fixed" by widening its allowlist
      // without someone also deleting this.
      for (final name in ['JWT_SECRET', 'DATABASE_URL']) {
        expect(
          secretNames(files['staging']!),
          isNot(contains(name)),
          reason: '$name must be a staging-specific secret',
        );
      }
    });

    test('every non-shared staging secret is namespaced', () {
      for (final name in secretNames(files['staging']!)) {
        if (deliberatelyShared.contains(name)) continue;
        expect(
          name,
          startsWith('STAGING_'),
          reason:
              'an un-namespaced secret name in the staging file is either a '
              'production secret or a new secret nobody will recognise as '
              "staging's when reading `gcloud secrets list`",
        );
      }
    });
  });

  group('channels staging must not have', () {
    test('push is explicitly disabled, and no FCM credential is mounted', () {
      // Not merely absent: `PUSH_PROVIDER=disabled` is checked ABOVE the FCM
      // build so that "no push here" stays distinguishable from "someone forgot
      // FCM", which still fails fast.
      expect(plainEnv(files['staging']!, 'PUSH_PROVIDER'), 'disabled');
      expect(
        secretNames(files['staging']!),
        isNot(contains('FCM_PRIVATE_KEY')),
      );
      expect(
        plainEnv(files['staging']!, 'FCM_PROJECT_ID'),
        isNull,
        reason:
            'pointing staging at production Firebase puts staging pushes on '
            'real phones',
      );
    });

    test('SMS is explicitly disabled in both', () {
      for (final entry in files.entries) {
        expect(
          plainEnv(entry.value, 'MESSAGING_PROVIDER'),
          'disabled',
          reason:
              '${entry.key}: unset falls through to auto-detect → null → '
              'the fail-fast, which is a boot failure rather than a channel',
        );
      }
    });

    test('AUTH_METHODS is identical, and never unset', () {
      // Load-bearing in both: unset makes `explicit` false, which turns ALL
      // four methods on — including phone, which can deliver in neither — and
      // simultaneously silences the Google/Apple/Resend fail-fasts.
      final prod = plainEnv(files['prod']!, 'AUTH_METHODS');
      expect(prod, isNotNull);
      expect(plainEnv(files['staging']!, 'AUTH_METHODS'), prod);
    });

    test("staging's CORS allowlist contains no production origin", () {
      final origins = (plainEnv(files['staging']!, 'WEB_ORIGINS') ?? '').split(
        ',',
      );
      for (final o in origins) {
        expect(
          o,
          isNot(contains('myweli.com')),
          reason:
              'the fix for a CORS-blocked preview is always to add a staging '
              'origin, never to widen the list toward production',
        );
      }
    });
  });

  group('the subset both files claim is identical', () {
    // `service-staging.yaml`'s header says "everything not called out below is
    // deliberately identical". That is a claim about two files, so it is a
    // claim nothing but a test can keep. The realistic drift is one-sided
    // tuning: someone shortens production's `failureThreshold` after a slow
    // deploy and staging — where minScale 0 makes every request a cold start —
    // keeps the old value, so the environment that exercises the path hardest
    // is the one no longer testing what production does.
    YamlMap container(YamlMap svc, String name) =>
        (podSpec(svc)['containers'] as YamlList).firstWhere(
              (c) => c['name'] == name,
            )
            as YamlMap;

    test('the app container: probes, port and resources', () {
      final p = container(files['prod']!, 'app');
      final s = container(files['staging']!, 'app');
      expect(s['startupProbe'].toString(), p['startupProbe'].toString());
      expect(s['livenessProbe'].toString(), p['livenessProbe'].toString());
      expect(s['resources'].toString(), p['resources'].toString());
      expect(s['ports'].toString(), p['ports'].toString());
    });

    test('the proxy sidecar: same pinned image, probe and resources', () {
      final p = container(files['prod']!, 'cloudsql-proxy');
      final s = container(files['staging']!, 'cloudsql-proxy');
      expect(
        s['image'],
        p['image'],
        reason:
            'an unpinned or divergent proxy version makes the two '
            'environments disagree about the one component that sits between '
            'the app and its database',
      );
      expect(s['startupProbe'].toString(), p['startupProbe'].toString());
      expect(s['resources'].toString(), p['resources'].toString());
      // Everything except the instance name, which is the point of the file.
      final pArgs = (p['args'] as YamlList).toList()..removeLast();
      final sArgs = (s['args'] as YamlList).toList()..removeLast();
      expect(sArgs, pArgs);
    });

    test('the boot-ordering fixes and the request timeout', () {
      for (final key in [
        'run.googleapis.com/container-dependencies',
        'run.googleapis.com/startup-cpu-boost',
      ]) {
        expect(
          templateAnnotations(files['staging']!)[key],
          templateAnnotations(files['prod']!)[key],
          reason: key,
        );
      }
      expect(
        podSpec(files['staging']!)['timeoutSeconds'],
        podSpec(files['prod']!)['timeoutSeconds'],
        reason:
            'migrations and five seed/backfill steps run before the port '
            'opens in both',
      );
    });

    test('TZ is UTC in both — timestamps must not mean two things', () {
      expect(plainEnv(files['prod']!, 'TZ'), 'UTC');
      expect(plainEnv(files['staging']!, 'TZ'), 'UTC');
    });
  });

  group('the deploy substitutions', () {
    test('both files still carry the placeholders the workflow replaces', () {
      for (final name in ['service.yaml', 'service-staging.yaml']) {
        final raw = File('$root/infra/gcp/$name').readAsStringSync();
        expect(raw, contains('__IMAGE__'), reason: name);
        expect(
          raw,
          contains('__RELEASE__'),
          reason:
              '$name: without this, RELEASE deploys as the literal string and '
              'Sentry groups every error under "no release" — which is release '
              'health not working while looking configured',
        );
      }
    });

    test('there is no THIRD placeholder nobody substitutes', () {
      // A `__SOMETHING__` the workflow does not know about deploys verbatim.
      final known = {'__IMAGE__', '__RELEASE__'};
      for (final name in ['service.yaml', 'service-staging.yaml']) {
        final raw = File('$root/infra/gcp/$name').readAsStringSync();
        final found = RegExp(
          r'__[A-Z_]+__',
        ).allMatches(raw).map((m) => m.group(0)!).toSet();
        expect(found.difference(known), isEmpty, reason: name);
      }
    });
  });

  group('scaling arithmetic, per file', () {
    // Both environments are on a db-f1-micro with no `databaseFlags` override,
    // so both inherit the default 25 and Postgres keeps 3 back for superusers.
    const usable = 25 - 3;

    int scale(YamlMap svc, String key) => int.parse(
      templateAnnotations(svc)['autoscaling.knative.dev/$key'] as String,
    );

    for (final entry in files.entries) {
      test('${entry.key}: a fully scaled-out revision fits its instance', () {
        // kMaxConnectionsPerInstance is 4 — see db/pool_sizing_test.dart for the
        // narrative. Here the point is that it holds for EACH file's own
        // maxScale, so raising staging's does not quietly break the arithmetic
        // that only production's was ever checked against.
        const perInstance = 4;
        expect(
          perInstance * scale(entry.value, 'maxScale'),
          lessThanOrEqualTo(usable),
          reason: '${entry.key}: raise the Cloud SQL tier before maxScale',
        );
      });
    }

    test('staging scales to zero and production does not', () {
      // Opposite values for opposite reasons, both deliberate: production must
      // never let user traffic trigger the cold start that serialises behind
      // the schema advisory lock; staging must, because that is the path worth
      // rehearsing — and because the compute should not join the Cloud SQL
      // instance in being unable to scale to zero.
      expect(scale(files['prod']!, 'minScale'), greaterThanOrEqualTo(1));
      expect(scale(files['staging']!, 'minScale'), 0);
    });
  });
}
