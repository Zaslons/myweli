import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/dart_source.dart';

/// The app never promises what the product does not do.
///
/// ## Why this file exists
///
/// The promo-video honesty sweep (2026-10-19) found three sentences that sold
/// something the server does not deliver: « Acompte payé en ligne » on the Pro
/// deposit screen (the client pays by Mobile Money straight to the salon —
/// MyWeli never holds money), the Pro dashboard's push prompt promising a
/// notification when a client « modifie » a booking (the salon is never told
/// about a client reschedule), and — on the web — reminders « WhatsApp/SMS »
/// while production runs `MESSAGING_PROVIDER=disabled`.
/// Design: docs/design/promise-honesty-sweep.md §5.
///
/// ## How it holds
///
/// Each family of phrases stands on a fact about the product, and the test
/// **reads that fact** rather than assuming it. When the fact changes —
/// messaging is switched on, or the salon starts hearing about reschedules —
/// the matching test goes red and says « re-decide this pin », instead of the
/// pin quietly forbidding copy that has become true, or quietly letting it
/// back while it is still false.
///
/// It reads every Dart file under `lib/` (comments stripped, adjacent literals
/// joined, apostrophes in one spelling, case ignored — the conventions of
/// `pro_subscription_no_pricing_test.dart`, whose self-tests cover the shared
/// helpers) and the store-listing sections of the two store-form docs, since
/// those are the apps' texts too.
void main() {
  group('the facts the pins stand on', () {
    test('production messaging (WhatsApp/SMS) is still off', () {
      expect(
        _messagingProvider(File('../infra/gcp/service.yaml').readAsStringSync()),
        'disabled',
        reason:
            'infra/gcp/service.yaml no longer runs MESSAGING_PROVIDER=disabled '
            '— messaging may be ON. Re-decide the « messaging channel » pin '
            'below (and the web one, web/tests/promise-honesty-pin.test.ts): '
            'the copy it forbids may now be true.',
      );
    });

    test('the salon is still not told when a client reschedules', () {
      final events = _salonEvents(
        File(
          '../backend/lib/src/messaging/salon_notifier.dart',
        ).readAsStringSync(),
      );
      expect(
        events.where(_isReschedule),
        isEmpty,
        reason:
            'SalonEvent now has a reschedule event ($events). The salon is '
            'told — re-decide the « reschedule » pin below: « …annule ou '
            'modifie un rendez-vous » may come back.',
      );
    });
  });

  group('no app text promises what the product does not do', () {
    test('lib/: none of the false phrases', () {
      final code = {
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File && f.path.endsWith('.dart'))
            f.path: _norm(stripDartComments(f.readAsStringSync())),
      };
      expect(code, isNotEmpty, reason: 'the scan found no Dart file');
      final hits = _hits(code);
      expect(
        hits,
        isEmpty,
        reason:
            'a sentence promises what the product does not do — say what it '
            'does today (docs/design/promise-honesty-sweep.md §2): $hits',
      );
    });

    test('the store listings: none of the false phrases', () {
      final listings = {
        'play-store-forms.md §1': _section(
          File('../docs/design/play-store-forms.md').readAsStringSync(),
          '## 1 ·',
        ),
        'app-store-forms.md §4': _section(
          File('../docs/design/app-store-forms.md').readAsStringSync(),
          '## 4 ·',
        ),
      };
      // Proof each section was found and holds the listing, not a stub.
      expect(listings['play-store-forms.md §1'], contains('acompte'));
      expect(listings['app-store-forms.md §4'], contains('acompte'));
      final hits = _hits(listings);
      expect(
        hits,
        isEmpty,
        reason:
            'a store listing promises what the product does not do — the '
            'owner submits these texts, so flag it to them: $hits',
      );
    });
  });

  group('the pin can fail', () {
    test('each family catches its phrase in code', () {
      for (final MapEntry(key: family, value: phrases) in _forbidden.entries) {
        for (final phrase in phrases) {
          final code = _norm(stripDartComments("final s = '$phrase';"));
          expect(
            _hits({'probe.dart': code}),
            isNotEmpty,
            reason: '$family: « $phrase » was not caught',
          );
        }
      }
    });

    test('the shipped sentences are caught — wrapped, quoted, any case', () {
      for (final source in [
        // The deposit label, as it shipped.
        "label: 'Acompte payé en ligne',",
        // The dashboard prompt, wrapped by `dart format` across literals.
        "body: 'Soyez prévenu·e dès qu’un client réserve, annule ou modifie '\n"
            "    'un rendez-vous, et ne manquez aucune demande.',",
        // The web offer line, in another case.
        "'RAPPELS AUTOMATIQUES WHATSAPP/SMS (24 H / 2 H)'",
      ]) {
        expect(
          _hits({'probe.dart': _norm(stripDartComments(source))}),
          isNotEmpty,
          reason: source,
        );
      }
    });

    test('a comment quoting the old copy is not a hit', () {
      expect(
        _hits({
          'probe.dart': _norm(
            stripDartComments("// was « Acompte payé en ligne »\nfinal s = 1;"),
          ),
        }),
        isEmpty,
      );
    });

    test('the fact readers read what they claim to', () {
      expect(
        _messagingProvider(
          '            - name: MESSAGING_PROVIDER\n'
          '              value: termii\n',
        ),
        'termii',
      );
      expect(
        () => _messagingProvider('- name: PUSH_PROVIDER\n  value: fcm\n'),
        throwsStateError,
        reason: 'a manifest without the entry must not read as « disabled »',
      );
      final events = _salonEvents(
        'enum SalonEvent { newBooking, clientRescheduled, clientCancelled }',
      );
      expect(events, ['newBooking', 'clientRescheduled', 'clientCancelled']);
      expect(events.where(_isReschedule), ['clientRescheduled']);
      expect(() => _salonEvents('class Nope {}'), throwsStateError);
    });
  });
}

/// The false promises, by the fact that makes them false. Lower-case, one
/// apostrophe spelling (see [_norm]).
const _forbidden = <String, List<String>>{
  // Messaging is OFF in production until company registration
  // (`MESSAGING_PROVIDER=disabled`) — no WhatsApp, no SMS reaches anyone.
  'messaging channel': [
    'whatsapp/sms',
    'sms/whatsapp',
    'rappels automatiques whatsapp',
    'rappels whatsapp',
    'rappels sms',
    'rappel par sms',
    'rappel par whatsapp',
    'confirmations whatsapp',
    'confirmation whatsapp',
    'confirmation par whatsapp',
    'whatsapp reminders',
    'sms reminders',
  ],
  // No-custody, permanently: the client pays the deposit by Mobile Money to
  // the salon's own number and proves it with a screenshot.
  'online payment': [
    'payé en ligne',
    'payée en ligne',
    'paiement en ligne',
    'payez en ligne',
    'réglé en ligne',
    'pay online',
    'paid online',
    'online payment',
  ],
  // `SalonEvent` has no reschedule event: a client « Reporter » notifies the
  // client only, never the salon.
  'reschedule': ['annule ou modifie', 'modifie un rendez-vous'],
};

String _norm(String text) => asCopy(text).toLowerCase();

List<String> _hits(Map<String, String> normalised) => [
  for (final e in normalised.entries)
    for (final MapEntry(key: family, value: phrases) in _forbidden.entries)
      for (final phrase in phrases)
        if (e.value.contains(_norm(phrase))) '${e.key}: « $phrase » ($family)',
];

/// The `MESSAGING_PROVIDER` value in a Cloud Run manifest. Throws when the
/// entry is missing — an unread fact must never pass as « disabled ».
String _messagingProvider(String manifest) {
  final m = RegExp(
    r'-\s*name:\s*MESSAGING_PROVIDER\s*\n\s*value:\s*(\S+)',
  ).allMatches(manifest).toList();
  if (m.length != 1) {
    throw StateError('MESSAGING_PROVIDER found ${m.length}× in the manifest');
  }
  return m.single.group(1)!;
}

/// The members of `enum SalonEvent`. Throws when the enum is not found.
List<String> _salonEvents(String source) {
  final body = RegExp(
    r'enum\s+SalonEvent\s*\{([^}]*)\}',
  ).firstMatch(stripDartComments(source))?.group(1);
  if (body == null) throw StateError('enum SalonEvent not found');
  final members = [
    for (final raw in body.split(RegExp(r'[,;]')))
      if (RegExp(r'^\s*([A-Za-z_]\w*)').firstMatch(raw) case final m?)
        m.group(1)!,
  ];
  if (members.isEmpty) throw StateError('enum SalonEvent has no member');
  return members;
}

bool _isReschedule(String event) =>
    RegExp(r'resched|moved|modif|report', caseSensitive: false).hasMatch(event);

/// The text of the `## n ·` section that starts with [heading], up to the next
/// `## ` heading — normalised. Throws when the heading is missing.
String _section(String doc, String heading) {
  final start = doc.indexOf('\n$heading');
  if (start == -1) throw StateError('section « $heading » not found');
  final next = doc.indexOf('\n## ', start + 1);
  return _norm(doc.substring(start, next == -1 ? doc.length : next));
}
