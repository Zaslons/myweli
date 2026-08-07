// APNs probe — the only way to check that push registration actually works.
//
// Run it, do not import it. It lives in `tool/` rather than `lib/` so it is
// never part of the app:
//
//   flutter run -d <simulator-udid> --flavor consumer -t tool/apns_probe.dart \
//     --dart-define=USE_API_BACKEND=true --dart-define=API_BASE_URL=https://api.myweli.com
//
// **Why it exists.** Nothing else can answer whether #328's `aps-environment`
// entitlement works. The app only asks for push permission after a login
// (consumer: first booking; pro: first dashboard visit), so reaching the token
// through the UI needs live credentials. This drives the SAME adapter the app
// uses — `FcmPushNotificationService`, real Firebase, nothing mocked — and
// prints what iOS actually hands back.
//
// Firebase only initialises when `USE_API_BACKEND` is true, hence the define.
//
// Measured 2026-08-07 on an iPhone 13 mini simulator (iOS 26.5, Apple silicon):
// a real 160-char APNs token and a real FCM token. Remote push on the
// simulator needs macOS 13+ on Apple silicon; on an Intel Mac expect NULL, and
// that is the tooling, not the entitlement.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:myweli/core/push/firebase_bootstrap.dart';
import 'package:myweli/services/push/fcm_push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final lines = <String>[];
  void log(String s) {
    // ignore: avoid_print
    print('APNS_PROBE $s');
    lines.add(s);
  }

  final ok = await initFirebaseForPush();
  log('firebase.initialized=$ok');

  final push = FcmPushNotificationService();

  final before = await push.permissionStatus();
  log('permission.before=$before');

  final asked = await push.requestPermission();
  log('permission.afterRequest=$asked');

  // The APNs token is the thing #328 is about: no entitlement, no token, and
  // every later step is dead regardless of how correct it looks.
  final apns = await FirebaseMessaging.instance.getAPNSToken();
  log(
    'apns.token=${apns == null ? 'NULL' : '${apns.substring(0, 12)}… (${apns.length} chars)'}',
  );

  // FCM only issues its own token once it holds an APNs token.
  String? fcm;
  try {
    fcm = await push.getToken();
  } catch (e) {
    log('fcm.error=$e');
  }
  log('fcm.token=${fcm ?? 'NULL'}');

  runApp(_Probe(lines));
}

class _Probe extends StatelessWidget {
  const _Probe(this.lines);
  final List<String> lines;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SelectableText(
                      l,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
