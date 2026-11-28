import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/constants/app_constants.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/core/utils/salon_time.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/salon_client.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_clients_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/clients/client_detail_screen.dart';
import 'package:myweli/screens/provider/clients/client_list_screen.dart';
import 'package:myweli/screens/provider/journal/pro_journal_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_clients_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/widgets/common/app_chip.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/frozen_clock.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '_a11y.dart';

/// The client's name on three Pro screens, never cut and never squeezed
/// (docs/design/app-pro-client-name-legibility.md, SYSTEM.md §21 row 100).
///
/// **What was broken, measured on `main` (47e46cfd)**, real font:
/// - the client card cut every linked client's name at the DEFAULT size:
///   77 dp beside the badge and the actions at 360, « Aïcha Koné » 5 of 10;
/// - the list showed « Koffi Yao » as « … » alone at 360 × 2×, and a row with
///   real chips (MyWeli, 3 absences, 2 tags) overflowed by 111 dp;
/// - the journal showed « Jean Kouassi » 3 of 12 at 360 × 2×, and a booking
///   with absences and a deposit overflowed by 83 dp. Its deposit icon was
///   never heard.
///
/// **The data is §2's, not the seeds'.** The seeds have short names and few
/// chips; the defects are worst on a long name with several chips, and the
/// long-word fallback (§4.1, §4.3) only triggers on « Kouakoussou ».
///
/// **One `testWidgets` per screen, width and size**, and per client on the
/// card: `layout_test.dart`'s header says why a loop inside one test is green
/// about a screen that is broken.
///
/// DI: assigned by hand, never through `setupDependencyInjection()`. The
/// locator's fields are `late final`, and the clients have to be §2's.
void main() {
  /// §10's compact range.
  const widths = <double>[360, 375, 390];

  /// The default size, and §13.3's floor.
  const scales = <double>[1, 2];

  setUpAll(() async {
    AppClock.freeze(kFixedNow);
    await initializeDateFormatting('fr_FR', null);
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({'myweli_push_asked': true});
    stubSecureStorage();
    serviceLocator
      ..authService = MockAuthService()
      ..proService = MockProService()
      ..proTeamService = MockProTeamService()
      ..proClientsService = _Clients()
      ..proPushRegistration = PushRegistration(
        push: MockPushNotificationService(),
        devices: MockDeviceRegistrationService(),
      );
  });
  tearDownAll(AppClock.restore);

  setUp(() {
    // Re-seeds the bookings at the frozen instant, then §2's day joins the
    // seed's « Jean Kouassi » at 10:30 two days on.
    freezeClock(kFixedNow);
    MockData.appointments.addAll(_journalDay());
  });

  for (final width in widths) {
    for (final scale in scales) {
      final at = '${width.toInt()}dp × ${scale.toInt()}×';

      testWidgets('the client list at $at: each name whole, its chips under '
          'it', (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final auth = await signInPro(tester);
          await pumpPushedAtWidth(
            tester,
            width: width,
            scale: scale,
            height: 3000,
            providers: [
              ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
              ChangeNotifierProvider<ProClientsProvider>(
                create: (_) => ProClientsProvider(),
              ),
            ],
            subject: const ClientListScreen(),
            rounds: 8,
          );
          final where = 'the client list at $at';
          _expectGates(tester, where, [for (final c in _base()) c.displayName]);
          for (final c in _base()) {
            _expectListRow(tester, c, where);
          }
        } finally {
          semantics.dispose();
        }
      });

      for (final client in _base()) {
        testWidgets('the client card of « ${client.displayName} » at $at: '
            'the name whole, the badge and the actions under it', (
          tester,
        ) async {
          final auth = await signInPro(tester);
          await pumpPushedAtWidth(
            tester,
            width: width,
            scale: scale,
            height: 3000,
            providers: [
              ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
              ChangeNotifierProvider<ProClientsProvider>(
                create: (_) => ProClientsProvider(),
              ),
            ],
            subject: ClientDetailScreen(clientId: client.id),
            rounds: 8,
          );
          final where = 'the card of « ${client.displayName} » at $at';
          _expectGates(tester, where, [client.displayName]);
          _expectCardHeader(tester, client, where);
        });
      }

      testWidgets('the journal at $at: each name whole, its chips under it', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          final auth = await signInPro(tester);
          await pumpPushedAtWidth(
            tester,
            width: width,
            scale: scale,
            height: 3000,
            providers: [
              ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
              ChangeNotifierProvider<ProJournalProvider>(
                create: (_) => ProJournalProvider(),
              ),
              ChangeNotifierProvider<ProTeamProvider>(
                create: (_) => ProTeamProvider(),
              ),
            ],
            subject: const ProJournalScreen(),
            rounds: 10,
          );
          // The day the bookings are on, found from the week strip's own
          // Monday, as `pro_journal_day`'s golden does.
          final today = salonNow(now: kFixedNow);
          final monday = today.subtract(Duration(days: today.weekday - 1));
          final target = monday.add(Duration(days: today.weekday - 1 + 2));
          await tester.tap(find.text('${target.day}'));
          await settleMocks(tester, rounds: 10);

          final day = [
            MockData.appointments.firstWhere((a) => a.id == 'appointment1'),
            ..._journalDay(),
          ];
          final where = 'the journal at $at';
          _expectGates(tester, where, [
            for (final a in day) a.clientDisplayName!,
          ]);
          for (final a in day) {
            _expectJournalRow(tester, a, where);
          }
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}

// ---- the data (spec §2) ---------------------------------------------------

/// The seeds' three, and four a real base has: three words, a hyphen and an
/// apostrophe, a guest with no chip, and an eleven-letter word.
List<SalonClient> _base() => [
  SalonClient(
    id: 'sc1',
    displayName: 'Aïcha Koné',
    phone: '+2250700000001',
    tags: const ['VIP'],
    lastVisitAt: AppClock.now().subtract(const Duration(days: 3)),
    linked: true,
    visits: 12,
    noShows: 0,
  ),
  SalonClient(
    id: 'sc2',
    displayName: 'Koffi Yao',
    phone: '+2250700000002',
    tags: const [],
    lastVisitAt: AppClock.now().subtract(const Duration(days: 12)),
    linked: true,
    visits: 3,
    noShows: 2,
  ),
  const SalonClient(
    id: 'sc3',
    displayName: 'Tante Marie',
    phone: '+2250700000003',
    tags: ['Fidèle'],
    linked: false,
    visits: 1,
    noShows: 0,
  ),
  SalonClient(
    id: 'sc4',
    displayName: 'Adjoua Kouamé Konan',
    phone: '+2250700000004',
    tags: const ['VIP', 'Fidèle'],
    lastVisitAt: AppClock.now().subtract(const Duration(days: 1)),
    linked: true,
    visits: 8,
    noShows: 3,
  ),
  SalonClient(
    id: 'sc5',
    displayName: 'Marie-Laure N’Guessan',
    phone: '+2250700000005',
    tags: const ['Nouvelle'],
    lastVisitAt: AppClock.now().subtract(const Duration(days: 40)),
    linked: false,
    visits: 2,
    noShows: 1,
  ),
  const SalonClient(
    id: 'sc6',
    displayName: 'Fatoumata Ouédraogo',
    phone: '+2250700000006',
    tags: [],
    linked: false,
    visits: 0,
    noShows: 0,
  ),
  // « Kouakoussou » is 268 dp of `titleLarge` at 2×: wider than the 232 the
  // card's avatar leaves at 360 and the 262 at 390. 200 dp of the journal's
  // name style at 2×: wider than the 195 beside the time at 360.
  SalonClient(
    id: 'sc7',
    displayName: 'Abdoulkarim Kouakoussou',
    phone: '+2250700000007',
    tags: const ['VIP'],
    lastVisitAt: AppClock.now().subtract(const Duration(days: 20)),
    linked: true,
    visits: 4,
    noShows: 2,
  ),
];

/// §2's bookings, on the seed's « Jean Kouassi » day (now + 2 days).
List<Appointment> _journalDay() {
  final day = AppClock.now().add(const Duration(days: 2));
  Appointment at(
    String id,
    int hours,
    String name,
    AppointmentStatus status, {
    int noShows = 0,
    double deposit = 0,
    int services = 1,
  }) => Appointment(
    id: id,
    userId: 'user_$id',
    providerId: const SalonId('provider1'),
    serviceIds: [for (var i = 1; i <= services; i++) 'service$i'],
    appointmentDate: day.add(Duration(hours: hours)),
    status: status,
    totalPrice: 5000.0 * services,
    depositAmount: deposit,
    clientNoShowCount: noShows == 0 ? null : noShows,
    clientDisplayName: name,
    createdAt: day.subtract(const Duration(days: 3)),
  );
  return [
    at(
      'names1',
      1,
      'Adjoua Kouamé Konan',
      AppointmentStatus.pending,
      noShows: 2,
      deposit: 5000,
      services: 2,
    ),
    at(
      'names2',
      2,
      'Marie-Laure N’Guessan',
      AppointmentStatus.confirmed,
      noShows: 1,
      deposit: 2000,
    ),
    at('names3', 3, 'Fatoumata Ouédraogo', AppointmentStatus.confirmed),
    at(
      'names4',
      4,
      'Abdoulkarim Kouakoussou',
      AppointmentStatus.confirmed,
      noShows: 2,
    ),
  ];
}

/// The mock's list and card, serving §2's base.
class _Clients extends MockProClientsService {
  @override
  Future<ApiResponse<SalonClientsPage>> listClients(
    SalonId providerId, {
    String? query,
    String? tag,
    int page = 1,
    int? pageSize,
  }) async {
    await Future<void>.delayed(AppConstants.mockDelay);
    final items = page == 1 ? _base() : <SalonClient>[];
    return ApiResponse.success(
      SalonClientsPage(
        items: items,
        page: page,
        total: _base().length,
        pageSize: MockProClientsService.pageSize,
      ),
    );
  }

  @override
  Future<ApiResponse<SalonClientCard>> getCard(
    SalonId providerId,
    String clientId,
  ) async {
    await Future<void>.delayed(AppConstants.mockDelay);
    final client = _base().firstWhere((c) => c.id == clientId);
    return ApiResponse.success(
      SalonClientCard(
        client: client.copyWith(phoneEditable: !client.linked),
        stats: SalonClientStats(
          visits: client.visits,
          spentFcfa: client.visits * 15000,
          noShows: client.noShows,
          cancellations: 0,
        ),
        notes: const [],
      ),
    );
  }

  @override
  Future<ApiResponse<List<Appointment>>> getVisits(
    SalonId providerId,
    String clientId, {
    int page = 1,
  }) async {
    await Future<void>.delayed(AppConstants.mockDelay);
    return ApiResponse.success(const <Appointment>[]);
  }
}

// ---- the checks -----------------------------------------------------------

/// What the card's initial avatar and its gap take from the name's line:
/// `_Header._identityIndent` (a 24 dp radius and `spacingM`).
const double _avatarAndGap = 2 * 24 + AppTheme.spacingM;

/// §13.3's gates, and the names by name: a name the salon chooses between
/// may wrap between its words, never inside one (A13).
void _expectGates(WidgetTester tester, String where, Iterable<String> names) {
  expect(
    tester.takeException(),
    isNull,
    reason:
        'a layout exception on $where. Before the fix, a row with its real '
        'chips overflowed by up to 111 dp (spec §2.1)',
  );
  expectNoLegibilityCrush(tester, context: where);
  expectNoUndeclaredTruncation(tester, context: where);
  expectNoVerticalClip(tester, context: where);
  for (final name in names) {
    _expectBreaksOnlyBetweenWords(tester, name, '« $name » on $where');
    // Decision 2: never cut. The floor above passes a name cut after its
    // eighth character — « Fatoumata Ouédr… » on a guest card at 2× today.
    final p = _paragraphOf(tester, name);
    expect(
      p.didExceedMaxLines,
      isFalse,
      reason:
          '« $name » is cut on $where. Spec §5 decision 2: a name wraps '
          'between its words and is never cut',
    );
  }
}

/// A hyphen between two letters: the engine may break after it, and §13.3
/// calls that break legal (« Marie- » / « Laure »).
final RegExp _afterHyphen = RegExp(r'(?<=\p{L}-)(?=\p{L})', unicode: true);

/// [expectNoMidWordBreak], and for a hyphenated name its pieces.
///
/// That gate keeps a hyphen inside its word (`unbreakableTokens`, « on the
/// strict side »), so it calls « Marie- » / « Laure » a break inside a word,
/// and its doc says hyphenated labels are not named to it. A hyphenated name
/// is measured here piece by piece instead, in its own paragraph's style:
/// each piece must fit the box, so a break anywhere but after the hyphen
/// still fails. « Marie-Laure N'Guessan » at 360 × 2×: « Marie-Laure » needs
/// 242 dp of the card's 232, and is drawn « Marie- » / « Laure ».
void _expectBreaksOnlyBetweenWords(
  WidgetTester tester,
  String name,
  String where,
) {
  if (!_afterHyphen.hasMatch(name)) {
    expectNoMidWordBreak(tester, name, where);
    return;
  }
  final p = _paragraphOf(tester, name);
  for (final word in unbreakableTokens(name)) {
    for (final piece in word.split(_afterHyphen)) {
      final painter = TextPainter(
        text: TextSpan(text: piece, style: p.text.style),
        textDirection: TextDirection.ltr,
        textScaler: p.textScaler,
      )..layout();
      final needs = painter.width;
      painter.dispose();
      expect(
        p.size.width + 0.5,
        greaterThanOrEqualTo(needs),
        reason:
            '$where: the box is ${p.size.width.toStringAsFixed(1)} dp and '
            '« $piece » needs ${needs.toStringAsFixed(1)}, so it is broken '
            'inside a word. §13.3: a name wraps between its words, or after '
            'a hyphen',
      );
    }
  }
}

/// The name's own paragraph: exactly one on each of these screens.
RenderParagraph _paragraphOf(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    );

/// The width of [text]'s widest piece the engine may not break, in
/// [paragraph]'s own style and scale.
double _widestToken(RenderParagraph paragraph, String text) {
  var widest = 0.0;
  for (final token in unbreakableTokens(text)) {
    final painter = TextPainter(
      text: TextSpan(text: token, style: paragraph.text.style),
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  return widest;
}

/// Every chip of [scope] starts under [name]'s last line.
void _expectChipsUnder(
  WidgetTester tester,
  Finder scope,
  Rect name,
  int count,
  String what,
) {
  final chips = find.descendant(of: scope, matching: find.byType(AppChip));
  expect(chips, findsNWidgets(count), reason: '$what: the chips drawn');
  for (var i = 0; i < count; i++) {
    final chip = tester.widget<AppChip>(chips.at(i));
    expect(
      tester.getRect(chips.at(i)).top,
      greaterThanOrEqualTo(name.bottom - 0.5),
      reason:
          '$what: « ${chip.label} » is beside the name, not under it. Spec '
          '§4: the chips take a line under the name, at every size',
    );
  }
}

/// The list's row (spec §4.2): the name alone, then « MyWeli », the
/// absences and the first two tags on a line under it; heard in that order,
/// before the visits line.
void _expectListRow(WidgetTester tester, SalonClient c, String where) {
  final name = find.text(c.displayName);
  final tile = find.ancestor(of: name, matching: find.byType(ListTile));
  final what = '« ${c.displayName} » on $where';
  _expectChipsUnder(
    tester,
    tile,
    tester.getRect(name),
    (c.linked ? 1 : 0) + (c.noShows >= 1 ? 1 : 0) + math.min(c.tags.length, 2),
    what,
  );

  final heard = tester.getSemantics(name).label;
  final visits = heard.indexOf('+225');
  expect(visits, isNonNegative, reason: '$what: the visits line is heard');
  for (final tag in c.tags.take(2)) {
    expect(
      heard.indexOf(tag),
      allOf(isNonNegative, lessThan(visits)),
      reason:
          '$what: the tag « $tag » is heard after the visits line. It '
          'sits under the name now, so it is read with the name: « $heard »',
    );
  }
}

/// The card's header (spec §4.1): the name on its own line, the badge and
/// « Appeler » / « WhatsApp » under it; the avatar drawn exactly when the
/// name's longest word fits beside it.
void _expectCardHeader(WidgetTester tester, SalonClient c, String where) {
  final name = tester.getRect(find.text(c.displayName));
  if (c.linked) {
    expect(
      tester.getRect(find.text('MyWeli')).top,
      greaterThanOrEqualTo(name.bottom - 0.5),
      reason:
          '$where: the « MyWeli » badge is beside the name, not under it '
          '(spec §4.1)',
    );
  }
  for (final tip in ['Appeler', 'WhatsApp']) {
    final action = tester.getRect(
      find.ancestor(of: find.byTooltip(tip), matching: find.byType(IconButton)),
    );
    expect(
      action.top,
      greaterThanOrEqualTo(name.bottom - 0.5),
      reason:
          '$where: « $tip » sits beside the name. It acts on the number, '
          'and goes beside the number (spec §4.1)',
    );
  }

  // The branch taken, asserted as such (§13.3: « Assert the thing itself »).
  // Drawn: the word fits beside it, which `expectNoMidWordBreak` has read.
  // Not drawn: it would not have fitted.
  final avatars = find.byType(CircleAvatar).evaluate().where((e) {
    final r = tester.getRect(find.byElementPredicate((x) => x == e));
    return r.right <= name.left + 0.5 && r.top < name.bottom;
  });
  if (avatars.isEmpty) {
    final p = _paragraphOf(tester, c.displayName);
    final widest = _widestToken(p, c.displayName);
    expect(
      widest,
      greaterThan(p.constraints.maxWidth - _avatarAndGap),
      reason:
          '$where: the avatar was dropped, but the name\'s longest word '
          '(${widest.toStringAsFixed(1)} dp) fits beside it '
          '(${(p.constraints.maxWidth - _avatarAndGap).toStringAsFixed(1)} '
          'dp). Spec §4.1: it goes only when the word does not fit',
    );
  }
}

/// The journal's row (spec §4.3): the name on its own line, the status chip,
/// the absences and the deposit under it; the time beside the name exactly
/// when the name's longest word fits there, above it otherwise; the deposit
/// heard as « Acompte ».
void _expectJournalRow(WidgetTester tester, Appointment a, String where) {
  final text = a.clientDisplayName!;
  final nameFinder = find.text(text);
  final card = find.ancestor(of: nameFinder, matching: find.byType(Slidable));
  final name = tester.getRect(nameFinder);
  final what = '« $text » on $where';

  _expectChipsUnder(
    tester,
    card,
    name,
    1 + ((a.clientNoShowCount ?? 0) >= 1 ? 1 : 0),
    what,
  );
  final deposit = find.descendant(
    of: card,
    matching: find.byIcon(Icons.savings_outlined),
  );
  expect(deposit, findsNWidgets(a.depositAmount > 0 ? 1 : 0));
  if (a.depositAmount > 0) {
    expect(
      tester.getRect(deposit).top,
      greaterThanOrEqualTo(name.bottom - 0.5),
      reason: '$what: the deposit icon is beside the name, not under it',
    );
  }

  final times = find.descendant(
    of: card,
    matching: find.byWidgetPredicate(
      (w) => w is Text && RegExp(r'^\d\d:\d\d$').hasMatch(w.data ?? ''),
    ),
  );
  expect(times, findsNWidgets(2), reason: '$what: its start and its end');
  final rects = [for (var i = 0; i < 2; i++) tester.getRect(times.at(i))];
  final beside = rects.every((r) => r.right <= name.left + 0.5);
  final above = rects.every((r) => r.bottom <= name.top + 0.5);
  expect(
    beside != above,
    isTrue,
    reason: '$what: the time is either beside the name or above it',
  );
  if (above) {
    final p = _paragraphOf(tester, text);
    final widest = _widestToken(p, text);
    final room =
        p.constraints.maxWidth -
        rects.map((r) => r.width).reduce(math.max) -
        AppTheme.spacingM;
    expect(
      widest,
      greaterThan(room),
      reason:
          '$what: the time went above the name, but the name\'s longest '
          'word (${widest.toStringAsFixed(1)} dp) fits beside it '
          '(${room.toStringAsFixed(1)} dp). Spec §4.3',
    );
  }

  final heard = tester.getSemantics(nameFinder).label;
  expect(
    heard.contains('Acompte'),
    a.depositAmount > 0,
    reason:
        '$what: a deposit is heard as « Acompte », and only when there is '
        'one (spec §4.3). Heard: « $heard »',
  );
}
