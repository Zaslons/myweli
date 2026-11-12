import 'package:myweli_backend/src/email/salon_validation_emails.dart';
import 'package:myweli_backend/src/validation/salon_place_notice_repository.dart';
import 'package:test/test.dart';

import 'salon_place_notice_contract.dart';

/// The in-memory twin of decision 133's cap (migration 0045). The same
/// contract runs on Postgres in `db/postgres_repositories_test.dart`.
void main() {
  var n = 0;

  group('SalonPlaceNoticeRepository — the twin contract (in-memory)', () {
    salonPlaceNoticeContract(
      repo: InMemorySalonPlaceNoticeRepository.new,
      salon: () async => 'salon_${++n}',
    );
  });

  test('the cap\'s four kinds are the e-mail\'s four labels, in the same '
      'order — the summary lists by one, the e-mails by the other', () {
    expect(kPlaceNoticeFields, kPlaceFieldLabels.keys.toList());
  });

  test('the window is one hour', () {
    expect(kPlaceNoticeWindow, const Duration(hours: 1));
  });
}
