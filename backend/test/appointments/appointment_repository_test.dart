import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:test/test.dart';

import 'appointment_repository_contract.dart';

/// The in-memory twin under the same contract as Postgres
/// (`db/postgres_repositories_test.dart`). docs/design/appointment-currency-stamp.md §8.2.
void main() {
  group('InMemoryAppointmentRepository — the twin contract', () {
    appointmentRepositoryContract(repo: InMemoryAppointmentRepository.new);
  });
}
