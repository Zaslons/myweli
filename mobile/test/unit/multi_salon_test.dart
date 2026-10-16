import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_access_guard.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/salon_time.dart';
import 'package:myweli/models/provider_session.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/salon_membership_info.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';

/// Team access R6b — multi-salons in the app: the models, the mock world
/// (« Mes salons », selection, « Ajouter un salon » gates), the
/// ProAuthProvider switch/fallback/persistence plumbing, and the
/// ProSalonScope reset sweep. Design:
/// docs/design/team-access-r6-multi-salons.md §6.
class _ResetSpy implements SalonScoped {
  int resets = 0;
  @override
  void resetForSalonSwitch() => resets++;
}

void main() {
  setUpAll(() {
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = MockProService();
    serviceLocator.subscriptionService = MockSubscriptionService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() async {
    MockData.resetTeam();
    ProSalonScope.clear();
    // Fresh per-salon offer state each test (SETUP everywhere).
    (serviceLocator.subscriptionService as MockSubscriptionService)
        .resetForTests();
    await serviceLocator.authService.logoutProvider();
  });

  Future<ProAuthProvider> signInOwner() async {
    final auth = ProAuthProvider();
    await auth.requestEmailOtp('jean@salon-excellence.test');
    final ok = await auth.verifyEmailOtp(
      'jean@salon-excellence.test',
      auth.emailDevCode!,
    );
    expect(ok, isTrue, reason: 'owner login failed');
    // loadMySalons runs unawaited post-login — let it land.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return auth;
  }

  group('models', () {
    test('SalonMembershipInfo + MySalonsResult round-trip', () {
      final info = SalonMembershipInfo.fromJson(const {
        'salonId': 'p2',
        'salonName': 'Beauté Divine',
        'role': 'owner',
        'salonStatus': 'draft',
        'verified': true,
        'imageUrl': 'https://cdn/x.jpg',
      });
      expect(info.role, TeamRole.owner);
      expect(info.isDraft, isTrue);
      expect(SalonMembershipInfo.fromJson(info.toJson()), info);

      final result = MySalonsResult.fromJson({
        'items': [info.toJson()],
        'canAddSalon': true,
      });
      expect(result.items.single, info);
      expect(result.canAddSalon, isTrue);
    });

    test('unknown role falls back to the MINIMAL staff shape', () {
      expect(teamRoleFrom('superuser'), TeamRole.staff);
      expect(teamRoleFrom(null), TeamRole.staff);
    });

    test(
      'ProviderSession round-trips the R6 selection; legacy JSON parses',
      () {
        final user = ProviderUser(
          id: 'acc1',
          phoneNumber: '',
          businessName: '',
          businessType: BusinessType.other,
          email: 'x@y.test',
          createdAt: DateTime(2026),
        );
        final session = ProviderSession(
          token: 't',
          refreshToken: 'r',
          provider: user,
          selectedSalonId: 'p2',
        );
        final back = ProviderSession.fromJson(session.toJson());
        expect(back.selectedSalonId, 'p2');
        // copyWith keeps, replaces and clears.
        expect(back.copyWith().selectedSalonId, 'p2');
        expect(back.copyWith(selectedSalonId: 'p9').selectedSalonId, 'p9');
        expect(back.copyWith(clearSelectedSalon: true).selectedSalonId, isNull);
        // Legacy (pre-R6) sessions simply have no selection.
        final legacy = ProviderSession.fromJson({
          'token': 't',
          'provider': user.toJson(),
        });
        expect(legacy.selectedSalonId, isNull);
      },
    );
  });

  group('« Mes salons » (mock world)', () {
    test(
      'the seeded owner sees BOTH salons, owned first, no add gate yet',
      () async {
        final auth = await signInOwner();
        expect(auth.salons.map((s) => s.salonId), ['provider2', 'provider1']);
        expect(auth.salons.every((s) => s.isOwner), isTrue);
        expect(auth.hasMultipleSalons, isTrue);
        // No offer anywhere → the server-computed gate stays closed.
        expect(auth.canAddSalon, isFalse);
      },
    );

    test(
      'switchSalon: reshapes, persists, resets the per-salon fleet',
      () async {
        final auth = await signInOwner();
        expect(auth.activeSalonId, 'provider1');
        final spy = ProSalonScope.track(_ResetSpy());

        final ok = await auth.switchSalon('provider2');
        expect(ok, isTrue);
        expect(auth.activeSalonId, 'provider2');
        expect(auth.salonName, 'Beauté Divine');
        expect(auth.membership!.role, TeamRole.owner);
        expect(spy.resets, 1);
        expect(
          await serviceLocator.authService.getSelectedProviderSalon(),
          'provider2',
        );
      },
    );

    test('switchSalon refetches the salon MARKET facts — timezone + currency '
        '(multi-pays MP2)', () async {
      // Move provider2 to Gabon for this test only (the committed seeds stay
      // CI — demo realism); restore after.
      final i = MockData.providers.indexWhere((p) => p.id == 'provider2');
      final original = MockData.providers[i];
      MockData.providers[i] = original.copyWith(
        countryCode: 'GA',
        timezone: 'Africa/Libreville',
        currency: 'XAF',
      );
      addTearDown(() => MockData.providers[i] = original);

      final auth = await signInOwner();
      expect(auth.salonTimezone, kSalonTz);
      expect(auth.salonCurrency, 'XOF');

      expect(await auth.switchSalon('provider2'), isTrue);
      expect(auth.salonTimezone, 'Africa/Libreville');
      expect(auth.salonCurrency, 'XAF');
      expect(auth.salonCountryCode, 'GA');

      expect(await auth.switchSalon('provider1'), isTrue);
      expect(auth.salonTimezone, kSalonTz);
      expect(auth.salonCurrency, 'XOF');
    });

    test('cold start restores the switched-to salon', () async {
      final auth = await signInOwner();
      await auth.switchSalon('provider2');

      // A new provider instance = the app restarting on the same session.
      final restarted = ProAuthProvider();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(restarted.activeSalonId, 'provider2');
      expect(restarted.salonName, 'Beauté Divine');
    });

    test('a salon the account does NOT belong to is refused; the session '
        'stays put', () async {
      final auth = await signInOwner();
      final ok = await auth.switchSalon('provider3');
      expect(ok, isFalse);
      expect(auth.activeSalonId, 'provider1');
      expect(auth.isAuthenticated, isTrue);
    });

    test('revoked from the SELECTED salon → silent fallback to the default '
        '(never a sign-out)', () async {
      final auth = await signInOwner();
      await auth.switchSalon('provider2');
      expect(auth.activeSalonId, 'provider2');

      // The provider2 ownership disappears mid-session.
      MockData.teamMembers.removeWhere((m) => m.id == 'mem_owner2');

      ProAccessGuard.report('forbidden');
      await Future<void>.delayed(const Duration(milliseconds: 900));

      expect(auth.isAuthenticated, isTrue);
      expect(auth.activeSalonId, 'provider1');
      expect(auth.consumeRevokedNotice(), isNull);
    });

    test('logout clears the selection', () async {
      final auth = await signInOwner();
      await auth.switchSalon('provider2');
      await auth.logout();
      expect(auth.selectedSalonId, isNull);
      expect(auth.salons, isEmpty);
      expect(
        await serviceLocator.authService.getSelectedProviderSalon(),
        isNull,
      );
    });
  });

  group('« Ajouter un salon » (mock world)', () {
    test('gated on a live Réseau offer → reseau_required first', () async {
      final auth = await signInOwner();
      final created = await auth.addSalon(
        businessName: 'Salon Trois',
        businessType: BusinessType.salon,
      );
      expect(created, isNull);
      expect(auth.errorCode, 'reseau_required');
    });

    test(
      'with Réseau live: creates the draft, switches to it, lists it',
      () async {
        final auth = await signInOwner();
        // provider1 on a live Réseau offer (chosen on the web, in production).
        expect(
          (serviceLocator.subscriptionService as MockSubscriptionService)
              .startTrialIfAbsent('provider1', tier: SalonTier.reseau),
          isTrue,
        );

        final created = await auth.addSalon(
          businessName: 'Salon Trois',
          businessType: BusinessType.spa,
        );
        expect(created, isNotNull);
        expect(created!.salonStatus, 'draft');
        expect(created.role, TeamRole.owner);
        // Switched to the new salon; the list carries all three.
        expect(auth.activeSalonId, created.salonId);
        expect(auth.salons.length, 3);
        // Its own SETUP state: no offer on the new salon yet.
        final offer = await serviceLocator.subscriptionService
            .getSalonSubscription(created.salonId);
        expect(offer.code, 'no_offer');
      },
    );

    test('the new salon\'s FIRST publish starts its own trial — on Réseau, the '
        'offer it was added under (pro-companion-path §3.1)', () async {
      final auth = await signInOwner();
      final subs =
          serviceLocator.subscriptionService as MockSubscriptionService;
      subs.startTrialIfAbsent('provider1', tier: SalonTier.reseau);
      final created = await auth.addSalon(
        businessName: 'Salon Trois',
        businessType: BusinessType.salon,
      );

      final published = await serviceLocator.proService.publishSalon(
        created!.salonId,
      );
      expect(published.success, isTrue);
      final offer = await subs.getSalonSubscription(created.salonId);
      expect(offer.data!.status, SalonOfferStatus.trial);
      expect(offer.data!.tier, SalonTier.reseau);
    });
  });

  group(
    'publish starts the trial (mock mirror of pro-companion-path §3.1)',
    () {
      test('no offer row → publish succeeds and starts the ONE trial on Pro; '
          'per salon', () async {
        await signInOwner();
        final subs =
            serviceLocator.subscriptionService as MockSubscriptionService;

        final res = await serviceLocator.proService.publishSalon('provider1');
        expect(res.success, isTrue);
        final first = (await subs.getSalonSubscription('provider1')).data!;
        expect(first.status, SalonOfferStatus.trial);
        expect(first.tier, SalonTier.pro);

        // Salon 2 gets its OWN fresh trial; salon 1's is untouched.
        expect(
          (await serviceLocator.proService.publishSalon('provider2')).success,
          isTrue,
        );
        expect(
          (await subs.getSalonSubscription('provider2')).data!.status,
          SalonOfferStatus.trial,
        );
        expect(
          (await subs.getSalonSubscription('provider1')).data!.trialEndsAt,
          first.trialEndsAt,
        );
      });

      test('a live offer (e.g. chosen on the web) is kept as it is', () async {
        await signInOwner();
        final subs =
            serviceLocator.subscriptionService as MockSubscriptionService;
        subs.startTrialIfAbsent('provider1', tier: SalonTier.business);

        expect(
          (await serviceLocator.proService.publishSalon('provider1')).success,
          isTrue,
        );
        expect(
          (await subs.getSalonSubscription('provider1')).data!.tier,
          SalonTier.business,
        );
      });
    },
  );

  // The R6 sweep pin (docs/design/r6-salon-id-pin.md). It used to grep
  // lib/screens for the strings `provider?.providerId` / `provider!.providerId`,
  // and the salon export read `account?.providerId ?? account?.id` through a
  // local named `account` — two salons' data in one file after a switch. So
  // it no longer looks for a NAME: every `.providerId` read above the
  // service layer is counted, file by file and receiver by receiver, against
  // the reviewed list at the bottom of this file.
  group('the sweep pin', () {
    test('every `.providerId` read above the service layer has been '
        'reviewed — whatever its variable is called', () {
      final reads = providerIdReads(_appSources());
      expect(
        reads.entries
            .where((e) => !_alwaysParameter(e.key))
            .map((e) => '${e.key} ×${e.value.length}'),
        unorderedEquals(
          _reviewedProviderIdReads.entries.map(
            (e) => '${e.key} ×${e.value.reads}',
          ),
        ),
        reason:
            'A `.providerId` read changed. If it reads the SIGNED-IN '
            'ACCOUNT (a ProviderUser), it is the default salon, not the one '
            'the session acts in: use ProAuthProvider.activeSalonId. If it '
            'is another model\'s (a booking, a review), add or bump its line '
            'in _reviewedProviderIdReads with the reason. Reads now:\n'
            '${_describe(reads)}',
      );
    });

    test('no salon id is ever an `.id` (an account id is not a salon id)', () {
      final found = salonIdFromId(_appSources());
      expect(
        found.entries.map((e) => '${e.key} ×${e.value.length}'),
        unorderedEquals(
          _reviewedSalonIdFromId.entries.map(
            (e) => '${e.key} ×${e.value.reads}',
          ),
        ),
        reason:
            'A salon-id slot (`activeSalonId ?? …`, `providerId: …`, '
            '`final salonId = …`) is fed by an `.id`. The signed-in '
            'account\'s id is never a salon id: use '
            'ProAuthProvider.activeSalonId, or guard its null. If the `.id` '
            'is a SALON model\'s, add its line to _reviewedSalonIdFromId. '
            'Found:\n${_describe(found)}',
      );
    });

    test('the pin sees through names — planted aliases go red', () {
      // Each shape below is one that got past, or would get past, a grep
      // for a variable name. Comments are not reads.
      const planted = '''
        final account = auth.provider;
        final a = account?.providerId ?? account?.id; // the export's shape
        final b = context.read<ProAuthProvider>().provider!.providerId;
        final c = me
            .provider
            ?.providerId;
        final d = (auth.provider as ProviderUser).providerId;
        // provider?.providerId — quoted in a comment, not read
        /* provider!.providerId */
        service.create(salonId: owner.id);
        final e = auth.activeSalonId ?? auth.provider!.id;
        const f = {'providerId': pro.id};
        DepositSettingsScreen(providerId: widget.providerId);
        DepositSettingsScreen(
          providerId: context.read<ProAuthProvider>().provider!.id,
        );
        final salonId = me.id;
      ''';
      final sources = {'lib/screens/planted.dart': planted};

      expect(providerIdReads(sources).map((k, v) => MapEntry(k, v.length)), {
        'lib/screens/planted.dart · account': 1,
        'lib/screens/planted.dart · …provider': 1,
        'lib/screens/planted.dart · me.provider': 1,
        'lib/screens/planted.dart · …': 1,
        'lib/screens/planted.dart · widget': 1,
      });
      expect(salonIdFromId(sources).map((k, v) => MapEntry(k, v.length)), {
        'lib/screens/planted.dart · account': 1,
        'lib/screens/planted.dart · owner': 1,
        'lib/screens/planted.dart · auth.provider': 1,
        'lib/screens/planted.dart · pro': 1,
        'lib/screens/planted.dart · …provider': 1,
        'lib/screens/planted.dart · me': 1,
      });
    });

    test('the scan covers the layers a salon id is chosen in', () {
      final paths = _appSources().keys;
      for (final layer in const [
        'lib/screens/',
        'lib/providers/',
        'lib/widgets/',
        'lib/core/',
      ]) {
        expect(paths.any((p) => p.startsWith(layer)), isTrue, reason: layer);
      }
      // The DTO layer is where `providerId` is declared and (de)serialized.
      expect(paths.where((p) => p.startsWith('lib/models/')), isEmpty);
      expect(paths.where((p) => p.startsWith('lib/services/')), isEmpty);
      // And the export screen, the read that slipped past the old pin.
      expect(
        paths,
        contains('lib/screens/provider/profile/pro_data_export_screen.dart'),
      );
    });
  });
}

// ---- The sweep pin's scanner (docs/design/r6-salon-id-pin.md §3) -----------

/// Every Dart file a salon id is CHOSEN in: lib/ minus the DTO layer
/// (lib/models declares and (de)serializes `providerId`) and the service
/// layer (lib/services maps it to and from the wire).
Map<String, String> _appSources() {
  final sources = <String, String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll(r'\', '/');
    if (path.startsWith('lib/models/') || path.startsWith('lib/services/')) {
      continue;
    }
    sources[path] = entity.readAsStringSync();
  }
  return sources;
}

/// The source with its comments blanked (newlines kept, so line numbers
/// hold): a doc line that quotes `provider?.providerId` is not a read.
String _code(String source) => source
    .replaceAllMapped(
      RegExp(r'/\*[\s\S]*?\*/'),
      (m) => '\n' * '\n'.allMatches(m[0]!).length,
    )
    .replaceAll(RegExp(r'//[^\n]*'), '');

const _ident = r'[A-Za-z_$][\w$]*';

/// A dotted chain ending right where the read starts — `account?`,
/// `widget.appointment`, `me\n    .provider\n    ?` — null-aware and bang
/// tokens and line breaks included.
final _chainAtEnd = RegExp(
  '($_ident(?:\\s*[?!]?\\s*\\.\\s*$_ident)*)\\s*[?!]?\\s*\$',
);

/// What the read is ON, normalized: `account?` → `account`,
/// `widget.appointment` stays, a member of an expression the scan cannot
/// name (`context.read<X>().provider`) keeps a leading `…`, and an
/// expression with no name at all (a cast, a call) is `…`.
String _receiverOf(String code, int dot) {
  final before = code.substring(dot < 200 ? 0 : dot - 200, dot);
  final m = _chainAtEnd.firstMatch(before);
  if (m == null) return '…';
  final chain = m[1]!.replaceAll(RegExp(r'[\s?!]'), '');
  final lead = before.substring(0, m.start).trimRight();
  return lead.endsWith('.') ? '…$chain' : chain;
}

int _lineOf(String code, int offset) =>
    '\n'.allMatches(code.substring(0, offset)).length + 1;

/// Every `.providerId` read, keyed `path · receiver`, with its lines.
Map<String, List<int>> providerIdReads(Map<String, String> sources) {
  final reads = <String, List<int>>{};
  for (final MapEntry(key: path, value: source) in sources.entries) {
    final code = _code(source);
    for (final m in RegExp(r'\.\s*providerId\b').allMatches(code)) {
      final key = '$path · ${_receiverOf(code, m.start)}';
      (reads[key] ??= []).add(_lineOf(code, m.start));
    }
  }
  return reads;
}

/// Where a salon id is PUT: a fallback (`activeSalonId ?? …`,
/// `providerId ?? …`), a named argument or a map entry (`providerId: …`,
/// `'salonId': …`), an assignment (`final salonId = …`, `_providerId = …`).
final _salonSlot = RegExp(
  r"\b(?:activeSalonId|providerId|salonId)\s*\?\?"
  r"|\b(?:providerId|salonId)'?\s*:"
  r'|\b[\w$]*(?:providerId|salonId|ProviderId|SalonId)\s*=(?![=>])',
);

/// The expression that starts at [from], up to the first `,` or `;` or
/// closing bracket outside any bracket — so a value with calls and generics
/// (`context.read<ProAuthProvider>().provider!.id`) is read whole.
String _expressionAt(String code, int from) {
  var depth = 0;
  for (var i = from; i < code.length; i++) {
    final c = code[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) return code.substring(from, i);
      depth--;
    } else if ((c == ',' || c == ';') && depth == 0) {
      return code.substring(from, i);
    }
  }
  return code.substring(from);
}

/// Every salon-id slot whose value is (or falls back to) an `.id`, keyed
/// `path · receiver of the .id`, with its lines.
Map<String, List<int>> salonIdFromId(Map<String, String> sources) {
  final found = <String, List<int>>{};
  for (final MapEntry(key: path, value: source) in sources.entries) {
    final code = _code(source);
    for (final slot in _salonSlot.allMatches(code)) {
      for (final operand in _expressionAt(code, slot.end).split('??')) {
        final value = operand.replaceAll(RegExp(r'[\s?!]'), '');
        if (!value.endsWith('.id')) continue;
        final head = value.substring(0, value.length - 3);
        final m = _chainAtEnd.firstMatch(head);
        final receiver = m == null
            ? '…'
            : head.substring(0, m.start).endsWith('.')
            ? '…${m[1]}'
            : m[1]!;
        (found['$path · $receiver'] ??= []).add(_lineOf(code, slot.start));
      }
    }
  }
  return found;
}

/// `this.providerId` declares a widget's parameter and `widget.providerId`
/// reads it back: the salon question moves to where the widget is BUILT,
/// and that site is itself a `.providerId` read (counted) or an `.id` in a
/// `providerId:` slot (refused).
bool _alwaysParameter(String key) =>
    key.endsWith(' · this') || key.endsWith(' · widget');

String _describe(Map<String, List<int>> reads) =>
    (reads.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => '  ${e.key} ×${e.value.length} (lines ${e.value})')
        .join('\n');

/// The reviewed `.providerId` reads that are NOT the signed-in account's:
/// each is another model's salon id (a booking, a review), or the resolver
/// itself. A new read anywhere — any variable name — is a new key or a new
/// count, and stays red until it is reviewed here.
const _reviewedProviderIdReads = <String, ({int reads, String why})>{
  // ProAuthProvider IS the resolver: `activeSalonId` (selection → the
  // account's default → the membership's salon), and `can`'s fallback for a
  // linked owner before any membership has loaded.
  'lib/providers/pro_auth_provider.dart · _provider': (
    reads: 2,
    why: 'the activeSalonId resolver and the pre-membership owner fallback',
  ),
  // A booking's salon (Appointment.providerId).
  'lib/screens/home/home_screen.dart · a': (
    reads: 1,
    why: 'the salon of an upcoming booking (consumer home)',
  ),
  'lib/screens/appointments/reschedule_screen.dart · widget.appointment': (
    reads: 1,
    why: 'the slots of the salon the booking is at',
  ),
  'lib/screens/appointments/my_bookings_screen.dart · appointment': (
    reads: 1,
    why: '« Réserver à nouveau » at the booking’s salon',
  ),
  'lib/screens/appointments/appointment_detail_screen.dart · appointment': (
    reads: 1,
    why: 'the review sheet for the booking’s salon',
  ),
  'lib/screens/providers/provider_detail_screen.dart · a': (
    reads: 1,
    why: 'the consumer’s bookings at this salon',
  ),
  'lib/widgets/booking/appointment_card.dart · appointment': (
    reads: 1,
    why: 'the salon card of a booking',
  ),
  'lib/providers/appointment_provider.dart · a': (
    reads: 1,
    why: 'a duplicate-booking check on the booking’s salon',
  ),
  'lib/providers/pro_journal_provider.dart · booking': (
    reads: 1,
    why: 'a created booking is kept only for the day’s salon',
  ),
  'lib/providers/pro_clients_provider.dart · booking': (
    reads: 1,
    why: 'a created booking reaches the client card of its salon only',
  ),
  'lib/providers/pro_dashboard_provider.dart · booking': (
    reads: 1,
    why: 'a created booking refreshes the dashboard of its salon only',
  ),
  'lib/core/utils/data_export.dart · a': (
    reads: 1,
    why: 'a booking’s salon, written into the export',
  ),
  // A review's salon (Review.providerId).
  'lib/providers/provider_provider.dart · review': (
    reads: 1,
    why: 'the salon a posted review is for',
  ),
  'lib/providers/provider_provider.dart · posted': (
    reads: 1,
    why: 'the salon to re-read after a posted review',
  ),
};

/// The reviewed salon-id slots fed by an `.id` — each the id of a SALON
/// model, never of an account.
const _reviewedSalonIdFromId = <String, ({int reads, String why})>{
  'lib/widgets/booking/appointment_card.dart · provider': (
    reads: 1,
    why: 'a salon (models.Provider) — its id IS the salon id',
  ),
  'lib/providers/provider_provider.dart · salon': (
    reads: 1,
    why: 'the salon just shown (models.Provider), remembered as selected',
  ),
  'lib/screens/provider/salon_preview_screen.dart · salon': (
    reads: 1,
    why: 'the acting salon as GET /me/provider returned it',
  ),
};
