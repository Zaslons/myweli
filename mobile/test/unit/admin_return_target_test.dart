import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/router/admin_router.dart';

import '../support/dart_source.dart';

/// docs/design/salon-go-live-approval.md §4.1, §8.2 — the login's `from`
/// target. The admin e-mail links one request
/// (`https://admin.myweli.com/#/admin/salon-validations/{id}`); before, every
/// sign-in landed on the dashboard and the link was lost. `from` arrives in a
/// URL anyone can craft and hand to an admin, so only a place in this console
/// is honoured — everything else lands on the dashboard.
void main() {
  group('adminReturnTarget — what `from` may name', () {
    test('a place under /admin/ is accepted, as written', () {
      for (final from in [
        '/admin/salon-validations/provider_1730000000000000',
        '/admin/salon-validations',
        '/admin/kyc/acc_1',
        '/admin/providers/provider_1',
        '/admin/audit?page=2',
        '/admin/dashboard',
        '/admin/salons/caf%C3%A9',
      ]) {
        expect(adminReturnTarget(from), from, reason: from);
      }
    });

    test('anything else is refused, whole', () {
      for (final from in <String?>[
        null,
        '',
        // The login itself, and what is not under /admin/.
        '/admin',
        '/admin/',
        '/admin?from=/admin/kyc',
        '/adminx/kyc',
        '/administrator/kyc',
        '/dashboard',
        'admin/kyc',
        // Another host: protocol-relative, a scheme, a backslash.
        '//evil.example/admin/kyc',
        'https://evil.example/admin/kyc',
        'javascript:alert(1)',
        '/admin//evil.example',
        r'/admin/\evil.example',
        r'/admin\..\x',
        '/admin/%5Cevil.example',
        '/admin/%2F%2Fevil.example',
        '/admin/a%2Fb',
        // Climbing out of /admin/, plainly or encoded.
        '/admin/../x',
        '/admin/../admin/kyc',
        '/admin/%2e%2e/x',
        '/admin/%2E%2E/x',
        '/admin/./kyc',
        '/admin/kyc/..',
        '/admin/kyc/.',
        // A fragment, control characters, a malformed escape.
        '/admin/kyc#x',
        '/admin/kyc\n',
        '/admin/kyc\u0000',
        '/admin/kyc%zz',
        '/admin/kyc%',
        // Escapes that are not UTF-8: refused, never thrown.
        '/admin/%ff',
        '/admin/kyc%c3',
        '/admin/%e2%82',
        // Longer than any place in the console.
        '/admin/${'a' * 2048}',
      ]) {
        expect(adminReturnTarget(from), isNull, reason: '$from');
      }
    });
  });

  group('adminRedirect — the login carries `from`, the sign-in honours it', () {
    String? redirect(String location, {bool signedIn = false}) => adminRedirect(
      restoring: false,
      authenticated: signedIn,
      location: Uri.parse(location),
    );

    test('nothing moves while the stored session is being checked', () {
      expect(
        adminRedirect(
          restoring: true,
          authenticated: false,
          location: Uri.parse('/admin/kyc'),
        ),
        isNull,
      );
    });

    test('signed out: the login, carrying where the admin was going', () {
      final to = redirect('/admin/salon-validations/provider_1')!;
      expect(Uri.parse(to).path, '/admin');
      expect(
        Uri.parse(to).queryParameters['from'],
        '/admin/salon-validations/provider_1',
      );
      expect(redirect('/admin/audit?page=2'), isNotNull);
      expect(
        Uri.parse(redirect('/admin/audit?page=2')!).queryParameters['from'],
        '/admin/audit?page=2',
      );
    });

    test('signed out at a place whose escape is not UTF-8: the login, '
        'without it — never go_router\'s error page', () {
      expect(redirect('/admin/%ff'), '/admin');
      expect(redirect('/admin/kyc%c3'), '/admin');
    });

    test('signed out at the dashboard, or at the login: no `from`', () {
      expect(redirect('/admin/dashboard'), '/admin');
      expect(redirect('/admin'), isNull);
      expect(redirect('/admin?from=%2Fadmin%2Fkyc'), isNull);
    });

    test('signed in at the login: back to `from` — or the dashboard when '
        '`from` is missing or refused', () {
      expect(
        redirect(
          '/admin?from=%2Fadmin%2Fsalon-validations%2Fprovider_1',
          signedIn: true,
        ),
        '/admin/salon-validations/provider_1',
      );
      expect(redirect('/admin', signedIn: true), '/admin/dashboard');
      for (final from in [
        'https%3A%2F%2Fevil.example',
        '%2F%2Fevil.example',
        '%2Fadmin%2F..%2Fx',
        '%2Fadmin',
        '%2Fadmin%2F%25ff',
      ]) {
        expect(
          redirect('/admin?from=$from', signedIn: true),
          '/admin/dashboard',
          reason: from,
        );
      }
    });

    test('signed in elsewhere: stays', () {
      expect(redirect('/admin/kyc', signedIn: true), isNull);
    });

    test('the admin e-mail\'s hash link lands on the request after a '
        'sign-in', () {
      // The backend builds the link (salon_validation_emails.dart) — read,
      // not restated, so a change there fails here.
      final emails = asCopy(
        stripDartComments(
          File(
            '../backend/lib/src/email/salon_validation_emails.dart',
          ).readAsStringSync(),
        ),
      );
      const prefix = 'https://admin.myweli.com/#/admin/salon-validations/';
      expect(emails, contains("'$prefix\${Uri.encodeComponent(providerId)}'"));

      const id = 'provider_1730000000000000';
      final link = Uri.parse('$prefix${Uri.encodeComponent(id)}');
      // A hash URL: the console's location is the fragment.
      final location = Uri.parse(link.fragment);
      final toLogin = redirect(location.toString())!;
      final back = redirect(toLogin, signedIn: true);
      expect(back, '/admin/salon-validations/$id');
    });

    test('the router redirects through adminRedirect, on the location', () {
      final src = stripDartComments(
        File('lib/core/router/admin_router.dart').readAsStringSync(),
      );
      expect(
        src,
        contains(
          'redirect: (context, state) => adminRedirect(\n'
          '    restoring: auth.restoring,\n'
          '    authenticated: auth.isAuthenticated,\n'
          '    location: state.uri,\n'
          '  ),',
        ),
      );
    });
  });
}
