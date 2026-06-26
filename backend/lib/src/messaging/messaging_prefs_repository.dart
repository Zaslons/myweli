/// Per-phone promotional opt-out (transactional messages always send).
/// Design: docs/design/messaging-notifications.md §5.
abstract interface class MessagingPrefsRepository {
  Future<void> setOptedOut(String phone, bool optedOut);
  Future<bool> isOptedOut(String phone);
}

class InMemoryMessagingPrefsRepository implements MessagingPrefsRepository {
  final Set<String> _optedOut = {};

  @override
  Future<void> setOptedOut(String phone, bool optedOut) async {
    if (optedOut) {
      _optedOut.add(phone);
    } else {
      _optedOut.remove(phone);
    }
  }

  @override
  Future<bool> isOptedOut(String phone) async => _optedOut.contains(phone);
}
