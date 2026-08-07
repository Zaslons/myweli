import 'package:myweli_backend/src/messaging/messaging_models.dart';
import 'package:myweli_backend/src/messaging/messaging_provider.dart';
import 'package:test/test.dart';

/// Messaging deliberately switched off, as a supported production posture (G1).
///
/// MyWeli launches before company registration, and both SMS channels need a
/// registered entity (Termii's branded sender needs ARTCI; a WhatsApp business
/// number needs Meta verification). So production has to be able to boot with
/// **no SMS channel at all** — and until now it could not: `dependencies.dart`
/// refused `MESSAGING_PROVIDER=log` outright and otherwise demanded Termii or
/// Twilio credentials. The only ways to deploy were to lie or to buy.
///
/// The whole design rests on one property, which is what these tests pin: this
/// provider reports **failure**, where [LogMessagingProvider] reports success.
void main() {
  group('DisabledMessagingProvider', () {
    test('reports failure — the property the whole design rests on', () async {
      // `messaging_service.dart:61` writes `res.ok ? sent : failed` to the
      // outbox. So ok:false is not a detail: it is what makes the outbox an
      // honest record of what was never delivered, which is what you want the
      // day the channel is switched on and someone asks what was missed.
      final res = await DisabledMessagingProvider().send(
        to: '+2250700000000',
        channel: MessageChannel.sms,
        body: 'anything',
      );

      expect(res.ok, isFalse);
      expect(res.providerMessageId, isNull);
      expect(
        res.error,
        'messaging_disabled',
        reason: 'the outbox row must say WHY, not just that it failed',
      );
    });

    test('and that is exactly where it differs from the log provider', () {
      // Stated as a test because the two are one keyword apart in the selector
      // and it would be an easy, invisible "simplification" to alias them.
      // `dependencies.dart:585` refuses `log` in production precisely because
      // it answers ok:true — every message dropped while the outbox records
      // `sent`. If this pair ever agrees, that guard has been defeated.
      expect(() async {
        final disabled = await DisabledMessagingProvider().send(
          to: '+2250700000000',
          channel: MessageChannel.sms,
          body: 'x',
        );
        final log = await LogMessagingProvider().send(
          to: '+2250700000000',
          channel: MessageChannel.sms,
          body: 'x',
        );
        expect(disabled.ok, isNot(log.ok));
      }, returnsNormally);
    });

    test('every channel is off, not just SMS', () async {
      // WhatsApp is deferred on the same condition as SMS, and
      // `messaging_service.dart:46` retries over SMS when WhatsApp fails —
      // so a provider that was off for one channel and on for the other would
      // silently deliver half the traffic.
      for (final channel in MessageChannel.values) {
        final res = await DisabledMessagingProvider().send(
          to: '+2250700000000',
          channel: channel,
          body: 'x',
        );
        expect(res.ok, isFalse, reason: 'channel ${channel.name} must be off');
      }
    });

    test('it never throws — the adapter contract', () async {
      // `MessagingProvider.send` documents "must not throw — network/credential
      // failures come back as ok:false". `messaging_service` does catch, but it
      // swallows into a silent `return null`, losing the outbox row entirely.
      await expectLater(
        DisabledMessagingProvider().send(
          to: '',
          channel: MessageChannel.sms,
          body: '',
        ),
        completion(isA<ProviderSendResult>()),
      );
    });
  });
}
