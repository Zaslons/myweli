import 'dart:io';

import 'dart_source.dart';

/// The source that builds the app a root (`lib/main*.dart`) starts.
///
/// Usually the root itself. A root whose `main()` only hands over to another
/// root's `runProApp` — `lib/main_pro_android.dart`, which runs the iOS app's
/// own wiring with the Android extensions (pro-android-signup.md §5.1, P14) —
/// is checked through the root it delegates to: that is where its
/// `ReduceMotionObserver`, `ContentWidthCap` and `DefaultStatusBarStyle` live.
///
/// **Both halves are required** for a delegation: `import 'main_pro.dart'
/// show runProApp;` AND a `runProApp(` call, comments stripped. A root that
/// imports it and builds its own app anyway is judged on its own source, and
/// fails the pin it skipped.
File appRootSource(File root) {
  final code = stripDartComments(root.readAsStringSync());
  final import = RegExp(
    r'''^\s*import\s+'(main_\w+\.dart)'\s+show\s+runProApp\s*;''',
    multiLine: true,
  ).firstMatch(code);
  if (import == null || !RegExp(r'\brunProApp\(').hasMatch(code)) return root;
  return File('${root.parent.path}/${import.group(1)}');
}
