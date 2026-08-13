import 'package:myweli_backend/src/messaging/webhook_auth.dart';
import 'package:test/test.dart';

/// Authentication for `POST /webhooks/messaging/status`
/// (docs/design/messaging-notifications.md §5, BACKEND.md §7 T19).
///
/// **What this replaces.** The webhook accepted a shared secret as `?secret=` in
/// the query string — a credential in a URL, which lands in Cloud Run request
/// logs, load-balancer logs and browser history. T21 records that exact weakness
/// as removed from the cron routes; this route was missed, because the pin that
/// enforced the removal listed two file paths instead of scanning the tree. The
/// generalised pin lives in `no_secret_in_url_test.dart`.
///
/// **Why not simply a header.** Twilio's `StatusCallback` is a URL Twilio POSTs
/// to, and Twilio's webhook documentation is explicit that custom request
/// headers cannot be configured — so `X-Messaging-Secret` alone would have been
/// a mechanism the only real caller cannot use. §5 had already specified the
/// right answer (verify `X-Twilio-Signature`) and the code had never done it.
void main() {
  // Twilio's OWN published fixture, from twilio-python's
  // tests/unit/test_request_validator.py. Using their vector rather than one
  // computed here is the difference between proving the algorithm and
  // restating the implementation.
  const twilioToken = '12345';
  const twilioUrl = 'https://mycompany.com/myapp.php?foo=1&bar=2';
  const twilioParams = {
    'CallSid': 'CA1234567890ABCDE',
    'Digits': '1234',
    'From': '+14158675309',
    'To': '+18005551212',
    'Caller': '+14158675309',
  };
  const twilioExpected = 'RSOYDt4T1cUTdK1PDd93/VVr8B8=';

  group('computeTwilioSignature — against Twilio\'s published vector', () {
    test('reproduces the signature Twilio publishes', () {
      expect(
        MessagingWebhookAuth.computeTwilioSignature(
          url: twilioUrl,
          params: twilioParams,
          authToken: twilioToken,
        ),
        twilioExpected,
      );
    });

    test('parameter ORDER does not matter — they are sorted by name', () {
      // The failure this catches: signing in map-insertion order works for
      // every test written from one example and fails against a real Twilio
      // request, whose parameter order is not ours to choose.
      const shuffled = {
        'To': '+18005551212',
        'Caller': '+14158675309',
        'CallSid': 'CA1234567890ABCDE',
        'From': '+14158675309',
        'Digits': '1234',
      };
      expect(
        MessagingWebhookAuth.computeTwilioSignature(
          url: twilioUrl,
          params: shuffled,
          authToken: twilioToken,
        ),
        twilioExpected,
      );
    });

    test('every input is load-bearing — change one, the signature moves', () {
      // Paired with the vector above: without these, a function that returned a
      // constant would pass the first test.
      String sig({String? url, Map<String, String>? params, String? token}) =>
          MessagingWebhookAuth.computeTwilioSignature(
            url: url ?? twilioUrl,
            params: params ?? twilioParams,
            authToken: token ?? twilioToken,
          );
      expect(sig(url: 'https://mycompany.com/other'), isNot(twilioExpected));
      expect(sig(token: '12346'), isNot(twilioExpected));
      expect(
        sig(params: {...twilioParams, 'Digits': '1235'}),
        isNot(twilioExpected),
      );
      expect(sig(params: const {}), isNot(twilioExpected));
    });
  });

  group('authenticate — the Twilio signature path', () {
    MessagingWebhookAuth auth({
      String? token = 'auth-token',
      String? secret,
      String? base = 'https://api.myweli.com',
    }) => MessagingWebhookAuth(
      twilioAuthToken: token,
      sharedSecret: secret,
      publicBaseUrl: base,
    );

    const path = '/webhooks/messaging/status';
    const fields = {'MessageSid': 'SM123', 'MessageStatus': 'delivered'};

    String signFor(String base, String token) =>
        MessagingWebhookAuth.computeTwilioSignature(
          url: '$base$path',
          params: fields,
          authToken: token,
        );

    test('a correct signature is accepted', () {
      final r = auth().authenticate(
        twilioSignature: signFor('https://api.myweli.com', 'auth-token'),
        headerSecret: null,
        requestPath: path,
        formFields: fields,
      );
      expect(r.ok, isTrue);
      expect(r.method, MessagingWebhookMethod.twilioSignature);
    });

    test('a wrong signature is refused', () {
      final r = auth().authenticate(
        twilioSignature: 'AAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        headerSecret: null,
        requestPath: path,
        formFields: fields,
      );
      expect(r.ok, isFalse);
    });

    test('a TAMPERED body invalidates the signature', () {
      // The property that makes this worth having over a shared secret: the
      // signature covers the parameters, so replaying a valid signature with a
      // different status does not work.
      final r = auth().authenticate(
        twilioSignature: signFor('https://api.myweli.com', 'auth-token'),
        headerSecret: null,
        requestPath: path,
        formFields: const {
          'MessageSid': 'SM123',
          'MessageStatus': 'undelivered',
        },
      );
      expect(r.ok, isFalse);
    });

    test('a signature for a DIFFERENT host is refused', () {
      // Why the signed URL is rebuilt from PUBLIC_BASE_URL and never from the
      // request's Host header: if the caller could choose the host, it could
      // choose part of the string its own signature is checked against.
      final r = auth().authenticate(
        twilioSignature: signFor('https://attacker.example', 'auth-token'),
        headerSecret: null,
        requestPath: path,
        formFields: fields,
      );
      expect(r.ok, isFalse);
    });

    test('a trailing slash on PUBLIC_BASE_URL does not break verification', () {
      final r = auth(base: 'https://api.myweli.com/').authenticate(
        twilioSignature: signFor('https://api.myweli.com', 'auth-token'),
        headerSecret: null,
        requestPath: path,
        formFields: fields,
      );
      expect(r.ok, isTrue);
    });
  });

  group('authenticate — the shared-secret fallback', () {
    test(
      'the matching header is accepted, and reported as the legacy path',
      () {
        final r =
            MessagingWebhookAuth(
              twilioAuthToken: null,
              sharedSecret: 's3cret',
              publicBaseUrl: null,
            ).authenticate(
              twilioSignature: null,
              headerSecret: 's3cret',
              requestPath: '/webhooks/messaging/status',
              formFields: const {},
            );
        expect(r.ok, isTrue);
        expect(
          r.method,
          MessagingWebhookMethod.sharedSecret,
          reason: 'the route logs this so there is evidence for when it can go',
        );
      },
    );

    test('a wrong or missing header secret is refused', () {
      final a = MessagingWebhookAuth(
        twilioAuthToken: null,
        sharedSecret: 's3cret',
        publicBaseUrl: null,
      );
      for (final supplied in [null, '', 'nope', 's3cre', 's3cretx']) {
        expect(
          a
              .authenticate(
                twilioSignature: null,
                headerSecret: supplied,
                requestPath: '/webhooks/messaging/status',
                formFields: const {},
              )
              .ok,
          isFalse,
          reason: 'supplied: $supplied',
        );
      }
    });

    test('a bad signature still falls through to the secret', () {
      // Deliberate, mirroring CronAuth: a misconfigured PUBLIC_BASE_URL must
      // not be able to take delivery tracking down on its own.
      final r =
          MessagingWebhookAuth(
            twilioAuthToken: 'auth-token',
            sharedSecret: 's3cret',
            publicBaseUrl: 'https://wrong.example',
          ).authenticate(
            twilioSignature: 'AAAA=',
            headerSecret: 's3cret',
            requestPath: '/webhooks/messaging/status',
            formFields: const {},
          );
      expect(r.ok, isTrue);
      expect(r.method, MessagingWebhookMethod.sharedSecret);
    });
  });

  group('isConfigured — deny by default', () {
    test('nothing configured → the endpoint does not exist', () {
      expect(
        MessagingWebhookAuth(
          twilioAuthToken: null,
          sharedSecret: null,
          publicBaseUrl: 'https://api.myweli.com',
        ).isConfigured,
        isFalse,
      );
    });

    test('a Twilio token with NO public base URL is not configured', () {
      // Without the base there is no URL to reconstruct, so no signature can be
      // checked — and an endpoint that answers while unable to verify anything
      // is the failure this whole change is about.
      expect(
        MessagingWebhookAuth(
          twilioAuthToken: 'auth-token',
          sharedSecret: null,
          publicBaseUrl: null,
        ).isConfigured,
        isFalse,
      );
    });

    test('either complete mechanism is enough', () {
      expect(
        MessagingWebhookAuth(
          twilioAuthToken: 'auth-token',
          sharedSecret: null,
          publicBaseUrl: 'https://api.myweli.com',
        ).isConfigured,
        isTrue,
      );
      expect(
        MessagingWebhookAuth(
          twilioAuthToken: null,
          sharedSecret: 's3cret',
          publicBaseUrl: null,
        ).isConfigured,
        isTrue,
      );
    });

    test('blank strings are unset, not configured', () {
      expect(
        MessagingWebhookAuth(
          twilioAuthToken: '  ',
          sharedSecret: '',
          publicBaseUrl: '  ',
        ).isConfigured,
        isFalse,
      );
    });
  });

  group('constantTimeEquals', () {
    test('equal strings match; unequal ones do not, at any length', () {
      expect(MessagingWebhookAuth.constantTimeEquals('abc', 'abc'), isTrue);
      expect(MessagingWebhookAuth.constantTimeEquals('abc', 'abd'), isFalse);
      expect(MessagingWebhookAuth.constantTimeEquals('abc', 'ab'), isFalse);
      expect(MessagingWebhookAuth.constantTimeEquals('abc', 'abcd'), isFalse);
      expect(MessagingWebhookAuth.constantTimeEquals('', ''), isTrue);
    });

    test('a shared prefix does not shortcut', () {
      // Not a timing measurement — that is not something a unit test can assert
      // reliably. This pins the behavioural half: no early return on the first
      // differing byte, and length folded in rather than compared separately.
      expect(
        MessagingWebhookAuth.constantTimeEquals('secret-value', 'secret-valuX'),
        isFalse,
      );
    });
  });
}
