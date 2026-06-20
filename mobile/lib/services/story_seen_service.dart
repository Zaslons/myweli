import 'package:shared_preferences/shared_preferences.dart';

class StorySeenService {
  static const _key = 'myweli_seen_story_ids_v1';

  StorySeenService._(this._prefs);
  final SharedPreferences _prefs;

  static Future<StorySeenService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StorySeenService._(prefs);
  }

  Set<String> getSeenIds() {
    return (_prefs.getStringList(_key) ?? const <String>[]).toSet();
  }

  Future<void> markSeen(String id) async {
    final set = getSeenIds();
    if (set.contains(id)) return;
    set.add(id);
    await _prefs.setStringList(_key, set.toList());
  }
}
