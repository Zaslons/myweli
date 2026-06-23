import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/dependencies.dart';

/// Custom dart_frog entrypoint: run DB migrations + seed (when `DATABASE_URL`
/// is configured) before the server starts accepting requests.
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) async {
  await initializeDatabase();
  return serve(handler, ip, port);
}
