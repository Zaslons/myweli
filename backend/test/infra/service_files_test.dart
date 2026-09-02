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

  /// Every `secretKeyRef` in a manifest, as {name, key} — the `key` half is
  /// what nothing looked at until secret drift turned out to be live.
  List<Map<String, dynamic>> secretRefs(YamlMap svc) => [
    for (final e in appEnv(svc))
      if (e['valueFrom']?['secretKeyRef'] != null)
        {
          'name': e['valueFrom']['secretKeyRef']['name'],
          'key': e['valueFrom']['secretKeyRef']['key'],
        },
  ];

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
      // GOOGLE_CLIENT_IDS and APPLE_CLIENT_IDS used to be here, for a reason
      // that is still true and is now enforced somewhere better: they are an
      // audience allowlist, so different values would mean staging accepts
      // tokens production rejects. They are also PUBLIC — they ship inside the
      // app binary — so they became plain `value:` entries in both manifests,
      // reviewable in a PR. The sameness is asserted directly below, on the
      // values themselves rather than on the fact that one secret feeds both.
      // The Cloudflare account id. A twin would be byte-identical, and two
      // copies of one value is drift waiting to happen. The R2 *credential* is
      // separate and bucket-scoped.
      'R2_ACCOUNT_ID',
      // The store-review demo sign-in code (T69). PUBLIC BY DESIGN — it is
      // printed into both stores' review notes — so sharing it with staging
      // discloses nothing. One value on purpose: staging is the rehearsal
      // for the demo salon's curation (backend-demo-review-account.md §9),
      // and one code in two environments is one code in the review notes.
      // What the secret buys is the KILL SWITCH (unset → the seam is absent)
      // and the pin monitor's watch, not confidentiality.
      'DEMO_PROVIDER_CODE',
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

    /// **What moving them out of Secret Manager must not lose.**
    ///
    /// Sharing one secret between the two services made divergence impossible
    /// by construction. Two plain literals can drift, so the property is now
    /// asserted rather than arranged — and asserted on the values, which is
    /// strictly stronger than the old check that merely saw the same secret
    /// NAME in both files.
    for (final name in ['GOOGLE_CLIENT_IDS', 'APPLE_CLIENT_IDS']) {
      test('$name is a plain value, identical in both files', () {
        final prod = plainEnv(files['prod']!, name);
        final staging = plainEnv(files['staging']!, name);

        expect(
          prod,
          isNotNull,
          reason:
              '$name is not a plain value in the production manifest. If it '
              'went back to a secretKeyRef, the reviewability this was moved '
              'for is gone and the test below cannot see the value at all',
        );
        expect(staging, isNotNull);
        expect(
          staging,
          prod,
          reason:
              'staging and production would accept different audiences, so a '
              'token minted for one is rejected by the other — the exact thing '
              'sharing a single secret used to make impossible',
        );
        expect(
          prod!.split(',').where((e) => e.trim().isNotEmpty),
          isNotEmpty,
          reason: 'an empty allowlist fails the boot guard on the next deploy',
        );
      });
    }

    test('neither is mounted as a secret any more', () {
      // Otherwise both forms could coexist, and which one wins would depend on
      // Cloud Run's ordering rather than on anything written down.
      for (final f in files.values) {
        expect(secretNames(f), isNot(contains('GOOGLE_CLIENT_IDS')));
        expect(secretNames(f), isNot(contains('APPLE_CLIENT_IDS')));
      }
    });

    /// **Secret versions are pinned, and `latest` is the defect.**
    ///
    /// Cloud Run resolves a secret reference at container start, and production
    /// runs minScale: 1 — one start per revision, ever. `latest` therefore left
    /// the running process holding whatever it read at boot while
    /// `gcloud secrets versions add` appeared to have applied. ADMIN_PASSWORD
    /// v2 sat unread for two days that way, against a v1 that was by then
    /// disabled.
    ///
    /// Nothing asserted the `key` at all before this, in either direction.
    group('secret versions are pinned', () {
      /// Anti-vacuity first: every assertion below loops over the mounts, so if
      /// `secretRefs` ever returns nothing — a reshaped manifest, a renamed
      /// key — the loops run zero times and this whole group passes while
      /// checking nothing.
      test('the mounts were actually found', () {
        for (final e in files.entries) {
          expect(
            secretRefs(e.value),
            hasLength(greaterThanOrEqualTo(12)),
            reason:
                '${e.key} parsed ${secretRefs(e.value).length} secret mounts, '
                'far fewer than it has — the shape this test reads has changed',
          );
        }
      });

      for (final e in files.entries) {
        test('${e.key}: no mount uses `latest`', () {
          final loose = secretRefs(
            e.value,
          ).where((r) => r['key'] == 'latest').map((r) => r['name']).toList();
          expect(
            loose,
            isEmpty,
            reason:
                'these resolve at container start and then never again, so a '
                'new version does not reach the running instance: $loose',
          );
        });

        test('${e.key}: every key is a quoted version number', () {
          for (final r in secretRefs(e.value)) {
            final key = r['key'];
            expect(
              key,
              isA<String>(),
              reason:
                  '${r['name']} has an unquoted key. YAML reads it as an '
                  'integer and the API wants a string — quote it',
            );
            expect(
              RegExp(r'^[1-9][0-9]*$').hasMatch(key as String),
              isTrue,
              reason:
                  '${r['name']} is pinned to "$key", which is not a version '
                  'number. `latest` is the value this group exists to reject, '
                  'and an alias is the same problem wearing a name',
            );
          }
        });
      }

      test('a secret mounted by both files is pinned to the same version', () {
        // They deploy independently, so two literals can drift where one shared
        // `latest` could not. The property is now asserted rather than arranged.
        final prod = {
          for (final r in secretRefs(files['prod']!)) r['name']: r['key'],
        };
        final staging = {
          for (final r in secretRefs(files['staging']!)) r['name']: r['key'],
        };
        final shared = prod.keys.toSet().intersection(staging.keys.toSet());
        expect(
          shared,
          isNotEmpty,
          reason: 'SENTRY_DSN and R2_ACCOUNT_ID are shared',
        );
        for (final name in shared) {
          expect(
            staging[name],
            prod[name],
            reason:
                '$name is pinned to v${prod[name]} in production and '
                'v${staging[name]} in staging, so the two environments hold '
                'different values for one secret',
          );
        }
      });
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

  group('the per-identity ceilings the code reads are actually declared', () {
    // Added 2026-08-20 after the runbook on the per-identity alert told an
    // operator to "set the matching LIMIT_* environment variable in
    // infra/gcp/service.yaml" when no such line was in that file — and was then
    // "corrected" to claim no such variable existed at all, which is worse,
    // because dependencies.dart reads all seven. Both halves of that mistake are
    // caught by the same assertion: the names the code reads, and the names the
    // manifests declare, have to be the same set.
    final deps = File(
      '$root/backend/lib/src/dependencies.dart',
    ).readAsStringSync();
    final read = RegExp(
      r"_envOrNull\('(LIMIT_[A-Z_]+)'\)",
    ).allMatches(deps).map((m) => m.group(1)!).toSet();

    test('dependencies.dart reads a non-empty set of them', () {
      // Without this, a rename in the code would empty the set and make every
      // assertion below vacuously true.
      expect(read, isNotEmpty);
      expect(read, contains('LIMIT_BOOKING'));
    });

    for (final env in files.entries) {
      test('${env.key} declares every one of them', () {
        final declared = <String>{
          for (final e in appEnv(env.value))
            if ((e['name'] as String).startsWith('LIMIT_')) e['name'] as String,
        };
        expect(
          declared,
          equals(read),
          reason:
              'a ceiling read by the code but absent here silently falls back '
              'to the compiled default, so the manifest an operator reads is '
              'not the configuration in force',
        );
      });

      test('${env.key} gives each a positive integer', () {
        for (final name in read) {
          final v = int.tryParse(plainEnv(env.value, name) ?? '');
          expect(v, isNotNull, reason: '$name is not a number');
          expect(
            v,
            greaterThan(1),
            reason:
                'warnAt(1) == 0 and real hits start at 1, so a ceiling of 0 or '
                '1 never warns — the surface goes silent without saying so',
          );
        }
      });
    }
  });

  group('the provisioning script provisions exactly what the manifest mounts', () {
    // Two files, one list, edited months apart. A secret added to the manifest
    // and forgotten in the script fails at REVISION CREATION with no
    // application log — the deploy just does not come up, and the reason is a
    // name in a YAML file nobody is looking at. The reverse, a secret created
    // and never mounted, is a credential minted for nothing.
    //
    // Found while writing that script: 13 `STAGING_*` twins plus 4 deliberately
    // shared with production is exactly the manifest's 17 mounts. This asserts
    // it stays that way.
    final script = File('$root/infra/gcp/90-staging.sh').readAsStringSync();

    Set<String> created() => RegExp(
      r'put_secret (STAGING_[A-Z0-9_]+)',
    ).allMatches(script).map((m) => m.group(1)!).toSet();

    Set<String> shared() {
      // The loop that grants read access on production's non-credential
      // secrets. Note the digit in `R2_ACCOUNT_ID` — a `[A-Z_]` class silently
      // drops it, which is how the first version of this check under-counted.
      final m = RegExp(r'for name in ([A-Z0-9_ ]+); do').firstMatch(script);
      return m == null
          ? {}
          : m.group(1)!.split(' ').where((s) => s.isNotEmpty).toSet();
    }

    test('every mounted secret is created or explicitly shared', () {
      expect(
        secretNames(files['staging']!).difference(created().union(shared())),
        isEmpty,
        reason:
            'mounted in service-staging.yaml but never provisioned — the '
            'revision will fail to create, with no application log to explain it',
      );
    });

    test('nothing is provisioned that the manifest does not mount', () {
      expect(
        created().union(shared()).difference(secretNames(files['staging']!)),
        isEmpty,
        reason: 'provisioned but unused — a credential minted for nothing',
      );
    });

    test('the shared four are exactly the ones the manifest shares', () {
      // Cross-checks the script against the SAME allowlist the secret-isolation
      // test above enforces, so the two cannot drift into disagreeing about
      // which secrets staging is allowed to read from production.
      expect(
        shared(),
        secretNames(
          files['prod']!,
        ).intersection(secretNames(files['staging']!)),
      );
    });

    test('the script never creates a secret without a STAGING_ prefix', () {
      for (final name in created()) {
        expect(name, startsWith('STAGING_'));
      }
    });
  });

  group('the deploy workflow still earns the WIF trust condition', () {
    // `infra/gcp/40-iam-wif.sh narrow` keys the deployer's trust on the
    // `environment` claim GitHub puts in the OIDC token — and GitHub only puts
    // it there when the JOB declares `environment:`. Delete that line and every
    // deploy fails at the auth step with a permission error naming a service
    // account, which reads like a GCP problem and is not.
    //
    // The two names must also match the two principalSets the script binds.
    // They are declared in two files that nothing else connects.
    final workflow = File(
      '$root/.github/workflows/deploy-backend.yml',
    ).readAsStringSync();
    final wifScript = File('$root/infra/gcp/40-iam-wif.sh').readAsStringSync();

    test('the job declares an environment', () {
      expect(
        RegExp(r'^\s{4}environment:', multiLine: true).hasMatch(workflow),
        isTrue,
        reason:
            'without a job-level `environment:` the OIDC token carries no '
            'environment claim, and the environment-scoped WIF bindings match '
            'nothing — see infra/gcp/40-iam-wif.sh',
      );
    });

    test('the environment names match the ones the WIF script binds', () {
      final bound = RegExp(r'ENVIRONMENTS=\(([a-z- ]+)\)')
          .firstMatch(wifScript)!
          .group(1)!
          .split(' ')
          .where((s) => s.isNotEmpty)
          .toSet();
      expect(bound, {'backend-staging', 'backend-production'});
      for (final env in bound) {
        // The workflow builds the name as `backend-\${{ inputs.environment }}`,
        // so what appears literally is the prefix plus each suffix.
        final suffix = env.substring('backend-'.length);
        expect(
          workflow,
          contains(suffix),
          reason:
              '$env is bound in the WIF script but the workflow never '
              'produces it',
        );
      }
    });

    test('the names are NOT Production/Preview, which Vercel already owns', () {
      // Reusing those would mix backend deploys into Vercel's deployment
      // activity log — and both already exist in the repo's environment list.
      expect(
        RegExp(
          r'^\s{4}environment:\s*(Production|Preview)\s*\$',
          multiLine: true,
        ).hasMatch(workflow),
        isFalse,
      );
    });
  });

  group('cron OIDC — the pair that must agree with the Scheduler job', () {
    // `CronAuth` verifies the Google-signed token only when BOTH are set. They
    // were absent from production for the whole life of the feature, so every
    // cron run authenticated on the shared `X-Cron-Secret` header while the
    // better mechanism looked configured.
    //
    // That header was retired on 2026-08-18, so these two are no longer the
    // BETTER mechanism — they are the ONLY one. Missing either now means the
    // route 404s and the crons stop, rather than quietly degrading to a
    // fallback (docs/design/infra-cron-oidc-evidence.md §8).
    test('both environments set both variables', () {
      for (final entry in files.entries) {
        for (final key in ['CRON_OIDC_AUDIENCE', 'CRON_SERVICE_ACCOUNT']) {
          expect(
            plainEnv(entry.value, key),
            isNotNull,
            reason:
                '${entry.key}: without $key the OIDC path is inert and '
                'CronAuth silently falls back to the shared secret',
          );
        }
      }
    });

    test('the audiences are DIFFERENT, and staging is not production', () {
      final prod = plainEnv(files['prod']!, 'CRON_OIDC_AUDIENCE')!;
      final staging = plainEnv(files['staging']!, 'CRON_OIDC_AUDIENCE')!;
      expect(prod, 'https://api.myweli.com');
      expect(
        staging,
        isNot(prod),
        reason:
            'staging carrying production\'s audience would name a host it '
            'is not, so every OIDC check fails and authenticate() falls through '
            'to the shared secret — configured, and doing nothing',
      );
      expect(
        staging,
        contains('.run.app'),
        reason:
            'staging has no load balancer; its audience is its own run.app '
            'URL — and specifically `status.url`, since Cloud Run publishes two '
            'hostnames for one service and only one is what the Scheduler job '
            'was pointed at',
      );
    });

    test('the service account is the Scheduler\'s, and shared', () {
      // Not a credential — it is the principal CronAuth pins the token to.
      // Without it the audience is a public string any Google account can mint
      // a token for, which is not a check.
      for (final entry in files.entries) {
        expect(
          plainEnv(entry.value, 'CRON_SERVICE_ACCOUNT'),
          'myweli-scheduler@myweli.iam.gserviceaccount.com',
          reason: entry.key,
        );
      }
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

    test('every REVISION states the commit it was built from', () {
      // Answering "what commit is production running?" used to take four steps
      // — find the deploy run, read its log, notice whether it PROMOTED a tag
      // or built one, map the tag back to a commit — and it is answerable
      // wrongly: run 32151417428 records headSha=d36fe475 while the image it
      // shipped was built from b64dda0, because it promoted. The label makes
      // the artifact answer for itself, and keeps answering correctly after a
      // rollback, because it rides on the REVISION rather than the service.
      for (final name in ['service.yaml', 'service-staging.yaml']) {
        final svc = load(name);
        final labels =
            svc['spec']['template']['metadata']['labels'] as YamlMap?;
        expect(
          labels?['commit'],
          '__RELEASE__',
          reason:
              '$name: the revision must carry its commit, on the TEMPLATE '
              '(revision) metadata — a service-level label reports the latest '
              'deploy even while an older revision serves',
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

  group('production promotes, and cannot quietly rebuild', () {
    final workflow = File(
      '$root/.github/workflows/deploy-backend.yml',
    ).readAsStringSync();

    test('a production dispatch with no image_tag is REFUSED', () {
      // The build step has always explained why a production rebuild is wrong
      // — it ships an artifact staging never ran, from a mutable
      // `FROM dart:stable` base. But the explanation only protected anything
      // if the operator remembered to fill in `image_tag`, which defaults to
      // empty, and forgetting it does the documented wrong thing SILENTLY:
      // the run succeeds and every log line agrees.
      expect(
        workflow,
        contains("github.event.inputs.environment == 'production'"),
        reason: 'the guard must test the environment',
      );
      expect(
        workflow,
        contains("github.event.inputs.image_tag == ''"),
        reason:
            'the guard must fire on the EMPTY tag — a guard that only checks '
            'the environment refuses every production deploy',
      );
      // Both halves in one `if:`, not two conditions that happen to appear.
      expect(
        workflow,
        contains(
          "if: \${{ github.event.inputs.environment == 'production' && "
          "github.event.inputs.image_tag == '' }}",
        ),
      );
    });

    test('and the refusal hands over a tag that has actually run', () {
      // Refusing without saying WHICH tag just moves the work to the operator,
      // who then looks it up by hand — which is where the wrong value comes
      // from. So the hint has to end in a concrete, correct value.
      expect(workflow, contains('myweli-api-staging'));
      expect(
        workflow,
        contains('spec.template.metadata.labels.commit'),
        reason: 'the commit label is the tag by construction — start there',
      );
      expect(
        workflow,
        contains(r'image_tag=${SUGGEST}'),
        reason: 'the operator must be handed a value, not a research task',
      );
    });

    test('the hint does not ask gcloud a question it answers with silence', () {
      // The first version of this hint read tags off a DIGEST reference:
      //   gcloud artifacts docker images describe IMAGE@sha256:… \
      //     --format='value(image_summary.tags)'
      // which returns EMPTY, so it printed "<none>" for a tag that existed.
      // Measured against the real registry on 2026-08-19 — by running the
      // guard, not by reading it. Both halves are asserted because either
      // alone would let it come back: the broken form must be gone, and the
      // form that works on a digest must be present.
      final hint = workflow
          .split('Production must promote')[1]
          .split('- name:')[0];
      expect(
        hint,
        isNot(contains('image_summary.tags')),
        reason:
            'that field is empty for a digest reference — use `artifacts docker '
            'tags list --filter=version:<digest>`, which is not',
      );
      expect(hint, contains('tags list'));
      expect(hint, contains(r'--filter="version:${STAGING_IMAGE##*@}"'));
    });

    test('and it VERIFIES the label rather than trusting it', () {
      // A commit label that does not resolve to the digest staging serves is a
      // label that is lying, and handing the operator a confident wrong tag is
      // worse than handing them nothing.
      expect(workflow, contains('image_summary.digest'));
      expect(
        workflow,
        contains(r'"${IMAGE}@${RESOLVED}" = "${STAGING_IMAGE}"'),
        reason: 'the suggestion is only offered when it provably matches',
      );
    });
  });

  group('the web rebuild hook is mounted on production and NOWHERE else', () {
    /// The inverse asymmetry to the one below, and for a sharper reason.
    ///
    /// The hook triggers a **production** Vercel build. Staging is precisely
    /// where salons get created and suspended while something is being tested,
    /// so mounting it there would have staging traffic spending money
    /// rebuilding the live site — and publishing whatever `main` happens to
    /// hold at that moment.
    ///
    /// Production needs it because the web's `/[slug]` sets
    /// `dynamicParams = false`, the only mechanism that serves a real 404 in
    /// the HTML, which fixes the slug set at BUILD time.
    /// docs/design/backend-web-rebuild-hook.md
    List<String> envNames(YamlMap svc) => [
      for (final e in podSpec(svc)['containers'][0]['env'] as YamlList)
        e['name'] as String,
    ];

    test('production mounts it', () {
      expect(envNames(files['prod']!), contains('WEB_DEPLOY_HOOK_URL'));
    });

    test('staging does NOT', () {
      expect(
        envNames(files['staging']!),
        isNot(contains('WEB_DEPLOY_HOOK_URL')),
        reason:
            'a staging salon change would trigger a PRODUCTION build — staging '
            'is where salons are created and suspended for testing',
      );
    });

    test('it comes from Secret Manager, never a literal', () {
      final env = podSpec(files['prod']!)['containers'][0]['env'] as YamlList;
      final e = env.firstWhere((x) => x['name'] == 'WEB_DEPLOY_HOOK_URL');
      expect(
        e['value'],
        isNull,
        reason:
            'a build-triggering URL inlined in a manifest is a leaked '
            'credential in git history',
      );
      expect(e['valueFrom']['secretKeyRef']['name'], 'WEB_DEPLOY_HOOK_URL');
    });
  });

  group('the OTP-disclosure seam is mounted on staging and NOWHERE else', () {
    /// The seam lets a caller holding `SMOKE_OTP_SECRET` read an OTP back for an
    /// identity in the RFC 2606 `.test` TLD. Staging needs it because the funnel
    /// harness has no other way in since the unconditional `devCode` echo was
    /// closed (docs/design/backend-staging-otp-disclosure.md).
    ///
    /// Production must never carry it as a matter of course. It is not that the
    /// seam is unsafe — two independent conditions bound it, and the `.test`
    /// suffix is a compile-time constant no environment value can widen — it is
    /// that a disclosure path present by DEFAULT on the real thing is a
    /// standing invitation, and the one that was once mounted there for a
    /// cutover was deliberately removed afterwards.
    List<String> envNames(YamlMap svc) => [
      for (final e in podSpec(svc)['containers'][0]['env'] as YamlList)
        e['name'] as String,
    ];

    test('staging mounts it', () {
      expect(envNames(files['staging']!), contains('SMOKE_OTP_SECRET'));
    });

    test('production does NOT', () {
      expect(
        envNames(files['prod']!),
        isNot(contains('SMOKE_OTP_SECRET')),
        reason:
            'a disclosure path present by default on production is a standing '
            'invitation. Mounting it for a cutover is a reviewed, temporary '
            'edit — not the committed state.',
      );
    });

    test('staging reads it from a STAGING_-prefixed secret', () {
      // Sharing production's secret would mean a staging leak is a production
      // leak, which is the whole reason every other staging secret is
      // separately named.
      final env =
          podSpec(files['staging']!)['containers'][0]['env'] as YamlList;
      final e = env.firstWhere((x) => x['name'] == 'SMOKE_OTP_SECRET');
      expect(
        e['valueFrom']['secretKeyRef']['name'],
        'STAGING_SMOKE_OTP_SECRET',
      );
    });

    test('90-staging.sh creates it, so a fresh project is not half-built', () {
      final script = File('$root/infra/gcp/90-staging.sh').readAsStringSync();
      expect(script, contains('STAGING_SMOKE_OTP_SECRET'));
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
      // Pre-launch economy (2026-08-30): prod deliberately runs 0 — an
      // always-on pod was ~2/3 of the GCP bill with zero public users.
      // LAUNCH.md §6.5 gates the flip back to ≥1 before announcing; when
      // that lands, this pin goes back to greaterThanOrEqualTo(1).
      expect(scale(files['prod']!, 'minScale'), 0);
      expect(scale(files['staging']!, 'minScale'), 0);
    });
  });
}
