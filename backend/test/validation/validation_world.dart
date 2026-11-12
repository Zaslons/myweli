import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/admin/admin_notifier.dart';
import 'package:myweli_backend/src/admin/admin_provider_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/email/send_budget.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/push/device_token_repository.dart';
import 'package:myweli_backend/src/push/push_provider.dart';
import 'package:myweli_backend/src/push/push_service.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';
import 'package:myweli_backend/src/site/site_rebuild_notifier.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_service.dart';
import 'package:myweli_backend/src/subscription/subscription_scheduler.dart';
import 'package:myweli_backend/src/validation/salon_decision_notifier.dart';
import 'package:myweli_backend/src/validation/salon_place_notice_repository.dart';
import 'package:myweli_backend/src/validation/salon_place_notice_service.dart';
import 'package:myweli_backend/src/validation/salon_validation_repository.dart';
import 'package:myweli_backend/src/validation/salon_validation_service.dart';
import 'package:test/test.dart';

/// Records what it was asked to do, so a call site can be observed.
class RecordingRebuild implements SiteRebuildNotifier {
  final reasons = <String>[];
  @override
  Future<void> requestRebuild(String reason) async => reasons.add(reason);
}

/// Every send, as it was handed over; [fail] answers `ok: false`, [explode]
/// throws (the contract says a provider must not — this is the belt).
class RecordingEmail implements EmailProvider {
  final sent =
      <
        ({
          String to,
          String subject,
          String text,
          String? html,
          EmailClass classification,
        })
      >[];
  bool fail = false;
  bool explode = false;

  @override
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
    required EmailClass classification,
    String? html,
  }) async {
    if (explode) throw StateError('smtp is down');
    sent.add((
      to: to,
      subject: subject,
      text: text,
      html: html,
      classification: classification,
    ));
    return fail
        ? (ok: false, providerMessageId: null, error: 'provider_down')
        : (ok: true, providerMessageId: 'm${sent.length}', error: null);
  }
}

/// Every push the provider was asked to send (one token per account).
class RecordingPushProvider implements PushProvider {
  final sends =
      <
        ({
          List<String> tokens,
          String title,
          String body,
          Map<String, String> data,
        })
      >[];

  @override
  Future<PushSendResult> send({
    required List<String> tokens,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    sends.add((tokens: tokens, title: title, body: body, data: data));
    return (sent: tokens.length, invalidTokens: const <String>[], error: null);
  }
}

/// An older image's publish (a rollback, §9.3) landing between the hand-back
/// and the going-live: once [armed], the salon leaves `draft` under the
/// validation's feet just before [goLive] runs.
class OlderImagePublishRacing extends InMemorySalonValidationRepository {
  OlderImagePublishRacing({required super.providers, required super.members})
    : _salons = providers;

  final InMemoryProvidersRepository _salons;
  bool armed = false;

  @override
  Future<GoLiveOutcome> goLive(String providerId, {DateTime? at}) async {
    if (armed) {
      armed = false;
      _salons.compareAndSetStatusNow(providerId, from: 'draft', to: 'active');
    }
    return super.goLive(providerId, at: at);
  }
}

/// A publish-ready profile (the go-live gate's thresholds). `Cocody` matches
/// a seeded area, so a request self-heals its market facts.
const Map<String, dynamic> completeProfile = {
  'description': 'Salon complet à Cocody.',
  'address': 'Rue des Jardins',
  'commune': 'Cocody',
  'latitude': 5.35,
  'longitude': -3.99,
  'imageUrls': ['a.jpg', 'b.jpg', 'c.jpg'],
  'services': [
    {'id': 's1', 'name': 'A', 'active': true},
    {'id': 's2', 'name': 'B', 'active': true},
    {'id': 's3', 'name': 'C', 'active': true},
  ],
  'availability': {
    'weeklySchedule': {
      '0': [
        {'startTime': '09:00', 'endTime': '18:00'},
      ],
    },
  },
};

/// B0.18's in-memory world: the repositories, the services built on them as
/// production wires them, and recorders for every outward effect (rebuilds,
/// e-mails to the owner and to the admin, pushes, the feed, the audit log).
class ValidationWorld {
  ValidationWorld({
    InMemorySalonValidationRepository Function(
      InMemoryProvidersRepository providers,
      InMemoryMembershipRepository members,
    )?
    validationsOf,
    InMemoryProvidersRepository? providers,
  }) : providers = providers ?? InMemoryProvidersRepository([]) {
    validations =
        validationsOf?.call(this.providers, members) ??
        InMemorySalonValidationRepository(
          providers: this.providers,
          members: members,
        );
  }

  final tokens = TokenService(secret: 'test-secret');
  late final InMemoryProviderAuthRepository auth =
      InMemoryProviderAuthRepository(tokens: tokens, echoDevCode: true);
  final InMemoryProvidersRepository providers;
  final members = InMemoryMembershipRepository();
  late final InMemorySalonValidationRepository validations;
  InMemorySalonSubscriptionRepository subs =
      InMemorySalonSubscriptionRepository();
  final rebuild = RecordingRebuild();
  final ownerMail = RecordingEmail();
  final adminMail = RecordingEmail();
  final pushes = RecordingPushProvider();
  final devices = InMemoryDeviceTokenRepository();
  late final push = PushService(pushes, devices);
  final feed = InMemoryNotificationsRepository();
  final audit = InMemoryAuditLogRepository();
  final adminLogs = <String>[];
  final placeNotices = InMemorySalonPlaceNoticeRepository();
  final placeLogs = <String>[];
  DateTime now = DateTime.utc(2026, 11, 12, 9);

  /// `ADMIN_EMAIL` as the composition root reads it.
  String? adminAddress = 'admin@myweli.com';

  SalonSubscriptionService get subscriptions => SalonSubscriptionService(
    subs,
    MembershipService(members, auth),
    members,
    providers,
    auth,
    clock: () => now,
    rebuild: rebuild,
    validations: validations,
  );

  AdminNotifier get adminNotifier =>
      AdminNotifier(adminMail, adminEmail: adminAddress, log: adminLogs.add);

  /// Decision 133's cap, on [placeNotices] and this world's clock.
  SalonPlaceNoticeService get placeNoticeService => SalonPlaceNoticeService(
    placeNotices,
    providers,
    validations,
    adminNotifier,
    clock: () => now,
    log: placeLogs.add,
  );

  SalonProvisioningService get provisioning => SalonProvisioningService(
    providers,
    auth,
    members,
    subscriptions: subscriptions,
    rebuild: rebuild,
    validations: validations,
    adminNotifier: adminNotifier,
    clock: () => now,
  );

  SalonDecisionNotifier get notice =>
      SalonDecisionNotifier(members, providers, push, feed, email: ownerMail);

  SalonValidationService get service => SalonValidationService(
    validations,
    providers,
    subscriptions,
    members,
    auth,
    audit,
    notice: notice,
    rebuild: rebuild,
    clock: () => now,
  );

  AdminProviderService get admin => AdminProviderService(
    providers,
    InMemoryAppointmentRepository(),
    audit,
    subscriptions,
    validations: validations,
    members: members,
    rebuild: rebuild,
  );

  SubscriptionScheduler scheduler({bool enforce = false}) =>
      SubscriptionScheduler(
        subs,
        members,
        providers,
        ownerMail,
        push,
        enforce: enforce,
        rebuild: rebuild,
        validations: validations,
      );

  var _n = 0;

  /// A `draft` salon owned by a fresh account with one app device —
  /// publish-ready unless [complete] is false. [phoneOwner]: the owner
  /// registered by phone, so the membership's `email` holds a phone number
  /// (the « @ » guard's case).
  Future<({String id, String ownerId})> salon({
    bool complete = true,
    bool phoneOwner = false,
    String name = 'Salon Awa',
    String? email,
  }) async {
    _n++;
    final mail = email ?? 'owner$_n@salon.pro';
    final reg = await auth.register(
      businessName: name,
      businessType: 'salon',
      phoneNumber: '+225050000${_n.toString().padLeft(4, '0')}',
      email: mail,
      authProvider: 'google',
      googleSub: 'sub-world-$_n',
    );
    final ownerId = reg.provider!.id;
    final created = await providers.createSalon(
      name: name,
      category: 'salon',
      phoneNumber: '+2250700000009',
    );
    final id = created['id'] as String;
    await members.ensureOwner(
      providerId: id,
      accountId: ownerId,
      email: phoneOwner ? '+225070000${_n.toString().padLeft(4, '0')}' : mail,
    );
    if (complete) await providers.updateProfile(id, completeProfile);
    await devices.upsert(
      token: 'tok-$ownerId',
      userId: ownerId,
      role: 'provider',
      platform: 'ios',
    );
    return (id: id, ownerId: ownerId);
  }

  /// The real path to « validated and live »: the owner's request, then the
  /// admin's validation. Asserts each step, so a test never starts from a
  /// state it only believes it reached.
  Future<void> validateLive(String id) async {
    final asked = await provisioning.publish(id);
    expect(asked.accepted, isTrue, reason: '${asked.error} ${asked.data}');
    final r = await service.approve(id, from: 'pending', adminId: 'admin_1');
    expect(r.ok, isTrue, reason: '${r.error} ${r.data}');
    expect((await providers.byId(id))!['status'], 'active');
  }

  /// The salon's status as stored.
  Future<String?> statusOf(String id) async =>
      (await providers.byId(id))?['status'] as String?;

  /// Whether the salon is in public discovery.
  Future<bool> isPublic(String id) async =>
      (await providers.query()).any((p) => p['id'] == id);
}
