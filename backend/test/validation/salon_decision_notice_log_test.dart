import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/email/send_budget.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/push/push_service.dart';
import 'package:myweli_backend/src/validation/salon_decision_notifier.dart';
import 'package:test/test.dart';

import 'validation_world.dart';

/// The salon's notice on each decision, as the log tells it (B0.18 —
/// docs/design/salon-go-live-approval.md §5.2, « Ce que dit le journal »):
/// one `salon_notice` line per channel — push, feed, e-mail — for every
/// decision, whatever happened, and nothing the salon or the admin typed.
///
/// The lines are asserted WHOLE: an extra field (an address, the note) or a
/// missing line fails the test, and the alert proposed in §5.2 matches
/// `channel=email outcome=failed` literally.
void main() {
  late ValidationWorld w;

  setUp(() => w = ValidationWorld());

  String line(String kind, String id, String channel, String outcome) =>
      'salon_notice kind=$kind provider=$id channel=$channel outcome=$outcome';

  group('every channel reached', () {
    test('a validation → three lines, push (by kind), feed, e-mail', () async {
      final s = await w.salon();
      await w.notice.approved(s.id);
      expect(w.noticeLogs, [
        line('approved', s.id, 'push', 'sent app=1 web=0'),
        line('approved', s.id, 'feed', 'sent'),
        line('approved', s.id, 'email', 'sent'),
      ]);
      expect(
        w.ownerMail.sent,
        hasLength(1),
        reason: 'the lines tell the truth',
      );
    });

    test(
      'a refusal → the same three lines, kind=refused, and NOTHING typed: '
      'not the note, the address, the salon name, the copy or a token',
      () async {
        const note = 'Photos floues — rappelez Awa au 0707070707';
        const address = 'awa.kone@salon-secret.ci';
        const name = 'Salon Zénith Cocody';
        final s = await w.salon(name: name, email: address);
        await w.notice.refused(s.id, code: 'photos', note: note);
        expect(w.noticeLogs, [
          line('refused', s.id, 'push', 'sent app=1 web=0'),
          line('refused', s.id, 'feed', 'sent'),
          line('refused', s.id, 'email', 'sent'),
        ]);
        // The control: the typed values did travel, to the salon.
        expect(w.ownerMail.sent.single.to, address);
        expect(w.ownerMail.sent.single.text, contains(note));
        final pushed = w.pushes.sends.single;
        for (final l in w.noticeLogs) {
          for (final secret in [
            note,
            'rappelez',
            address,
            'salon-secret',
            name,
            'Zénith',
            pushed.title,
            pushed.body,
            ...pushed.tokens,
            w.ownerMail.sent.single.subject,
            'photos', // the code is in the audit log, not here
          ]) {
            expect(l, isNot(contains(secret)), reason: 'leaked: $secret');
          }
        }
      },
    );

    test('the push reached a BROWSER only → sent app=0 web=1', () async {
      final s = await w.salon();
      await w.devices.remove('tok-${s.ownerId}');
      await w.devices.upsert(
        token: 'web-${s.ownerId}',
        userId: s.ownerId,
        role: 'provider',
        platform: 'web',
      );
      await w.notice.approved(s.id);
      expect(
        w.noticeLogs.first,
        line('approved', s.id, 'push', 'sent app=0 web=1'),
      );
    });
  });

  group('a channel that did not reach the owner says so', () {
    test('no device → push undelivered app=0 web=0; the feed and the e-mail '
        'still go', () async {
      final s = await w.salon();
      await w.devices.remove('tok-${s.ownerId}');
      await w.notice.refused(s.id, code: 'photos');
      expect(w.noticeLogs, [
        line('refused', s.id, 'push', 'undelivered app=0 web=0'),
        line('refused', s.id, 'feed', 'sent'),
        line('refused', s.id, 'email', 'sent'),
      ]);
    });

    test(
      'a phone-registered owner → e-mail skipped reason=no_address',
      () async {
        final s = await w.salon(phoneOwner: true);
        await w.notice.refused(s.id, code: 'photos');
        expect(w.noticeLogs, [
          line('refused', s.id, 'push', 'sent app=1 web=0'),
          line('refused', s.id, 'feed', 'sent'),
          line('refused', s.id, 'email', 'skipped reason=no_address'),
        ]);
        expect(w.ownerMail.sent, isEmpty);
      },
    );

    test(
      'the e-mail provider answers ok:false → failed error=<its code>',
      () async {
        final s = await w.salon();
        w.ownerMail.fail = true;
        await w.notice.refused(s.id, code: 'photos');
        expect(
          w.noticeLogs.last,
          line('refused', s.id, 'email', 'failed error=provider_down'),
        );
      },
    );

    test('the e-mail provider THROWS → failed error=<the type>, not its '
        'message', () async {
      final s = await w.salon();
      w.ownerMail.explode = true;
      await w.notice.approved(s.id);
      expect(
        w.noticeLogs.last,
        line('approved', s.id, 'email', 'failed error=StateError'),
      );
      expect(w.noticeLogs.last, isNot(contains('smtp is down')));
    });

    test(
      'an error that is no code (free text, an address) → error=unknown',
      () async {
        const address = 'awa@salon.ci';
        final s = await w.salon(email: address);
        final n = SalonDecisionNotifier(
          w.members,
          w.providers,
          w.push,
          w.feed,
          email: _AnsweringEmail('rejected $address: mailbox full'),
          log: w.noticeLogs.add,
        );
        await n.refused(s.id, code: 'photos');
        expect(
          w.noticeLogs.last,
          line('refused', s.id, 'email', 'failed error=unknown'),
        );
        for (final l in w.noticeLogs) {
          expect(l, isNot(contains(address)));
        }
      },
    );

    test('the push THROWS → push failed error=<type>; the feed and the '
        'e-mail still go', () async {
      final s = await w.salon();
      final n = SalonDecisionNotifier(
        w.members,
        w.providers,
        _ExplodingPush(w),
        w.feed,
        email: w.ownerMail,
        log: w.noticeLogs.add,
      );
      await n.approved(s.id);
      expect(w.noticeLogs, [
        line('approved', s.id, 'push', 'failed error=StateError'),
        line('approved', s.id, 'feed', 'sent'),
        line('approved', s.id, 'email', 'sent'),
      ]);
      expect(w.ownerMail.sent, hasLength(1));
    });

    test('the feed write THROWS → feed failed error=<type>; the e-mail '
        'still goes', () async {
      final s = await w.salon();
      final n = SalonDecisionNotifier(
        w.members,
        w.providers,
        w.push,
        _ExplodingFeed(),
        email: w.ownerMail,
        log: w.noticeLogs.add,
      );
      await n.refused(s.id, code: 'photos');
      expect(w.noticeLogs, [
        line('refused', s.id, 'push', 'sent app=1 web=0'),
        line('refused', s.id, 'feed', 'failed error=StateError'),
        line('refused', s.id, 'email', 'sent'),
      ]);
    });
  });

  group('nobody was told — every channel still has its line', () {
    test('no active owner linked to an account → three lines skipped '
        'reason=no_owner', () async {
      final created = await w.providers.createSalon(
        name: 'Orphelin',
        category: 'salon',
        phoneNumber: '+2250700000009',
      );
      final id = created['id'] as String;
      await w.notice.refused(id, code: 'photos');
      expect(w.noticeLogs, [
        // Written out, not read from `channels`: the order is pinned here.
        for (final c in ['push', 'feed', 'email'])
          line('refused', id, c, 'skipped reason=no_owner'),
      ]);
      expect(w.pushes.sends, isEmpty);
      expect(w.ownerMail.sent, isEmpty);
    });

    test('the owner lookup THROWS → three lines failed reason=lookup '
        'error=<type>; nothing sent', () async {
      final s = await w.salon();
      final n = SalonDecisionNotifier(
        _ExplodingMembers(),
        w.providers,
        w.push,
        w.feed,
        email: w.ownerMail,
        log: w.noticeLogs.add,
      );
      await n.refused(s.id, code: 'photos');
      expect(w.noticeLogs, [
        for (final c in ['push', 'feed', 'email'])
          line('refused', s.id, c, 'failed reason=lookup error=StateError'),
      ]);
      expect(w.pushes.sends, isEmpty);
      expect(w.ownerMail.sent, isEmpty);
    });
  });

  group('the decision is already written — the log never undoes it', () {
    test('a refusal whose e-mail fails: 200 and refused, and the log '
        'says the e-mail failed', () async {
      final s = await w.salon();
      await w.provisioning.publish(s.id);
      w.ownerMail.fail = true;
      final r = await w.service.refuse(
        s.id,
        code: 'photos',
        note: 'Floues',
        adminId: 'admin_1',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect((await w.validations.get(s.id))!.state, 'refused');
      expect(
        w.noticeLogs,
        contains(line('refused', s.id, 'email', 'failed error=provider_down')),
      );
    });

    test('a log sink that THROWS fails neither the notice nor the decision '
        '(refuse, then validate)', () async {
      w.noticeLog = (_) => throw StateError('log sink down');
      final refused = await w.salon();
      await w.provisioning.publish(refused.id);
      final r = await w.service.refuse(
        refused.id,
        code: 'photos',
        note: null,
        adminId: 'admin_1',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(
        w.ownerMail.sent,
        hasLength(1),
        reason: 'a throwing log line stops no channel',
      );
      expect(await w.feed.listForUser(refused.ownerId), hasLength(1));

      final approved = await w.salon();
      await w.provisioning.publish(approved.id);
      final a = await w.service.approve(
        approved.id,
        from: 'pending',
        adminId: 'admin_1',
      );
      expect(a.ok, isTrue, reason: '${a.error}');
      expect(await w.statusOf(approved.id), 'active');
      expect(w.ownerMail.sent, hasLength(2));
    });
  });

  group('errorCode', () {
    test('a code passes; anything else is unknown', () {
      for (final code in [
        'unroutable',
        'send_budget_exhausted',
        'resend_422',
        'resend_unreachable',
        'provider_down',
      ]) {
        expect(SalonDecisionNotifier.errorCode(code), code);
      }
      for (final bad in [
        null,
        '',
        'awa@salon.ci',
        'resend_500 outcome=sent',
        'Bad Request',
        'x' * 65,
      ]) {
        expect(SalonDecisionNotifier.errorCode(bad), 'unknown', reason: '$bad');
      }
    });
  });
}

/// Answers `ok: false` with [error], as a provider would.
class _AnsweringEmail implements EmailProvider {
  _AnsweringEmail(this.error);
  final String error;

  @override
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
    required EmailClass classification,
    String? html,
  }) async => (ok: false, providerMessageId: null, error: error);
}

/// A push service whose fan-out throws (its contract says it does not —
/// this is the belt the notifier wears).
class _ExplodingPush extends PushService {
  _ExplodingPush(ValidationWorld w) : super(w.pushes, w.devices);

  @override
  Future<PushDelivery> sendToUserByKind(
    String userId, {
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) => throw StateError('fcm is down');
}

class _ExplodingFeed extends InMemoryNotificationsRepository {
  @override
  Future<Map<String, dynamic>> add({
    required String userId,
    required String type,
    required String title,
    required String body,
    String? route,
  }) => throw StateError('db is down');
}

class _ExplodingMembers extends InMemoryMembershipRepository {
  @override
  Future<List<Member>> listForProvider(String providerId) =>
      throw StateError('db is down');
}
