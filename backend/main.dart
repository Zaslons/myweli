import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/dependencies.dart';
import 'package:myweli_backend/src/salon_time.dart';

/// Custom dart_frog entrypoint: load the tz database (multi-pays MP1), then
/// run DB migrations + seed (when `DATABASE_URL` is configured) before the
/// server starts accepting requests.
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) async {
  initSalonTime();
  await initializeDatabase();
  return serve(handler, ip, port);
}
