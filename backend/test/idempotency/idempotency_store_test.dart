import 'package:myweli_backend/src/idempotency/idempotency_store.dart';
import 'package:test/test.dart';

import 'idempotency_contract.dart';

void main() {
  group('InMemoryIdempotencyStore', () {
    idempotencyContract(store: (now) => InMemoryIdempotencyStore(now: now));
  });
}
