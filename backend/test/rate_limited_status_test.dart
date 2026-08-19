import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:test/test.dart';

/// `rate_limited` → **429**, wired before anything can emit it.
///
/// **That ordering is the whole point of this slice.** `storage_unavailable`
/// was added to the shared mapper first and to the bespoke switches later, and
/// `resultResponse`'s own doc comment records what that cost: *"a code added
/// here alone reaches two surfaces out of five"*. `routes/appointments/index.dart`
/// carries the same lesson twice over — two of its arms exist because a new code
/// shipped as a 400 and was caught afterwards.
///
/// So the mapping lands while the emitter does not yet exist, and this file is
/// what makes that claim checkable.
///
/// Design: docs/design/backend-identity-rate-limits.md §6
/// The three shapes a route uses to decide `badRequest` as its own FALLBACK.
///
/// Three, because the codebase writes the same idea three ways: a switch
/// expression yielding a status, one yielding a whole `Response`, and a
/// `default:` arm. A rule that knows only the first finds four routes where
/// there are eight — measured, after the first version of this test did
/// exactly that.
final kFallbackPatterns = [
  RegExp(r'_ => HttpStatus\.badRequest'),
  RegExp(r'_ => jsonError\(\s*\n?\s*HttpStatus\.badRequest'),
  RegExp(r'default:\s*\n\s*return jsonError\(\s*\n?\s*HttpStatus\.badRequest'),
];

void main() {
  Future<Map<String, dynamic>> bodyOf(Response r) async =>
      jsonDecode(await r.body()) as Map<String, dynamic>;

  group('the shared mapper', () {
    test('rate_limited is a 429, not the 400 default', () async {
      final r = resultResponse(ok: false, error: 'rate_limited', body: null);
      expect(r.statusCode, HttpStatus.tooManyRequests);
      expect(await bodyOf(r), {'error': 'rate_limited'});
    });

    test('and an unknown code still falls to 400', () async {
      // The control. Without it, a mapper that returned 429 for EVERYTHING
      // would pass the test above.
      final r = resultResponse(ok: false, error: 'something_else', body: null);
      expect(r.statusCode, HttpStatus.badRequest);
    });
  });

  group('the surfaces that will emit it', () {
    // Three surfaces, and they do not share a mapping. Two carry their own
    // switch; the third delegates. Both routes are asserted from source rather
    // than driven, because in this slice no service can produce the code yet —
    // the handler tests arrive with the emitters.

    test('POST /uploads/sign inherits it by delegating', () {
      final src = File('routes/uploads/sign.dart').readAsStringSync();
      expect(
        src,
        contains('resultResponse'),
        reason: 'this surface has no switch of its own — it must delegate',
      );
      // NOT "never mentions badRequest" — it has one, for an unparseable
      // body, and that is a parse failure rather than an error mapping. What
      // must not appear is a FALLBACK, which would silently override the
      // shared mapper.
      for (final pattern in kFallbackPatterns) {
        expect(
          pattern.hasMatch(src),
          isFalse,
          reason:
              'a bespoke fallback here would override resultResponse, which '
              'is exactly how the other two surfaces drifted',
        );
      }
    });

    test('POST /appointments names it in its own switch', () {
      expect(
        File('routes/appointments/index.dart').readAsStringSync(),
        contains("'rate_limited' => HttpStatus.tooManyRequests"),
      );
    });

    test('POST /appointments/{id}/review names it in its own switch', () {
      expect(
        File('routes/appointments/[id]/review.dart').readAsStringSync(),
        contains("case 'rate_limited':"),
      );
    });
  });

  test('EVERY ROUTE READING A LIMITED SERVICE MAPS THE CODE', () {
    // The derived gate, which slice 2 could not have: it needs emitters to
    // derive from, and there were none. Now there are three, so the set is
    // computed rather than declared — a FOURTH limited surface added later
    // would pass every named test above while quietly answering 400.
    //
    // Modelled on storage_unavailable_status_test.dart, including the two
    // things that make it worth having: an isNotEmpty guard so the scan cannot
    // go vacuous, and a declared opt-out so the exemption is visible.
    final limited = <String>{};
    for (final f in Directory('lib/src').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('security/')) continue; // the primitive itself
      final src = f.readAsStringSync();
      if (!src.contains("'rate_limited'")) continue;
      for (final m in RegExp(
        r'^class (\w+)',
        multiLine: true,
      ).allMatches(src)) {
        limited.add(m.group(1)!);
      }
    }
    expect(
      limited,
      isNotEmpty,
      reason:
          'the scan found no service that can emit rate_limited — it has '
          'drifted, and an empty set makes the assertion below vacuous. This '
          'is the guard slice 2 could not satisfy, which is why the gate was '
          'an inventory until the emitters existed.',
    );

    const marker = '// no-rate-limit:';
    final offenders = <String>[];
    final orphaned = <String>[];
    for (final f in Directory('routes').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      final reads = limited.any((c) => src.contains('context.read<$c>()'));
      if (!reads) {
        if (src.contains(marker)) orphaned.add(f.path);
        continue;
      }
      if (src.contains(marker)) continue;
      if (src.contains('resultResponse')) continue;
      if (src.contains('rate_limited')) continue;
      offenders.add(f.path);
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'these routes reach a service that can return rate_limited and '
          'neither delegate to resultResponse nor name the code, so a 429 '
          'falls to their 400 default. Add the arm, or declare `$marker` with '
          'a reason if the route genuinely cannot be limited.',
    );
    expect(
      orphaned,
      isEmpty,
      reason:
          'these declare `$marker` but no longer read a limited service. A '
          'stale exemption is how the next real one gets waved through.',
    );
  });

  test('NO TWELFTH BESPOKE MAPPING APPEARS UNNOTICED', () {
    // The forward guard, and the only test here that catches something nobody
    // is thinking about. A route that maps errors itself does NOT inherit
    // anything from `resultResponse`, so every one is a place a future code can
    // ship as a 400. The set is pinned rather than derived, because in this
    // slice there is no emitter to derive FROM — a scan for services that can
    // return `rate_limited` would find none and assert nothing, which is the
    // failure this repo keeps finding. The derived scan lands with the
    // emitters in slice 3.
    //
    // If this fails: a route gained its own error mapping. Decide whether it
    // can be rate-limited. If it can, add the arm. If it cannot, add it below
    // with a reason.
    const known = {
      // The two rate-limited surfaces that map errors themselves. The third,
      // POST /uploads/sign, delegates and so is deliberately absent here.
      'routes/appointments/index.dart': 'LIMITED — maps rate_limited',
      'routes/appointments/[id]/review.dart': 'LIMITED — maps rate_limited',

      // Not rate-limited, and each says why.
      'routes/appointments/[id]/deposit.dart':
          'one proof per booking; the SIGN step carries the limit instead',
      'routes/admin/client-version/index.dart': 'admin only',
      'routes/auth/provider/invitations/accept.dart':
          'identity-proven, one per invitation',
      'routes/auth/provider/invitations/decline.dart':
          'identity-proven, one per invitation',
      'routes/providers/[id]/appointments.dart':
          'salon-entered booking — capability-gated, not the client surface',
      'routes/providers/[id]/subscription.dart': 'salon owner only',
    };

    final found = <String>{};
    for (final f in Directory('routes').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      // A bespoke mapping is one that decides `badRequest` as its own FALLBACK
      // — either a switch-expression wildcard or a `default:` arm.
      if (kFallbackPatterns.any((p) => p.hasMatch(src))) found.add(f.path);
    }

    expect(
      found,
      isNotEmpty,
      reason:
          'the scan found no bespoke mapping at all — it has drifted, and an '
          'empty set makes this assertion vacuous',
    );
    expect(
      found.difference(known.keys.toSet()),
      isEmpty,
      reason:
          'these routes map errors themselves and are not declared above, so '
          'they inherit nothing from resultResponse and a future code will '
          'ship from them as a 400. Add the rate_limited arm, or list them '
          'with a reason.',
    );
    expect(
      known.keys.toSet().difference(found),
      isEmpty,
      reason:
          'these are declared above but no longer map errors themselves. A '
          'stale entry is how the next real one gets waved through — delete it.',
    );
  });
}
