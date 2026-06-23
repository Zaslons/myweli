import 'package:dart_frog/dart_frog.dart';

/// Root banner so hitting the API base returns something useful rather than 404.
Response onRequest(RequestContext context) {
  return Response.json(
    body: {'name': 'myweli-api', 'status': 'ok', 'health': '/health'},
  );
}
