import 'package:postgres/postgres.dart';

/// Builds a lazily-connecting Postgres connection pool from a `DATABASE_URL`
/// (`postgres://user:pass@host:port/db`). Connections are opened on demand, so
/// this is safe to construct synchronously in the composition root.
///
/// TLS is disabled only for local hosts (dev/CI); everything else requires it.
Pool<void> createPool(String databaseUrl) {
  final uri = Uri.parse(databaseUrl);
  final userInfo = uri.userInfo.split(':');
  final endpoint = Endpoint(
    host: uri.host.isEmpty ? 'localhost' : uri.host,
    port: uri.hasPort ? uri.port : 5432,
    database: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'postgres',
    username: userInfo.isNotEmpty && userInfo.first.isNotEmpty
        ? userInfo.first
        : null,
    password: userInfo.length > 1 && userInfo[1].isNotEmpty
        ? userInfo[1]
        : null,
  );
  final isLocal = endpoint.host == 'localhost' || endpoint.host == '127.0.0.1';
  return Pool<void>.withEndpoints(
    [endpoint],
    settings: PoolSettings(
      maxConnectionCount: 8,
      sslMode: isLocal ? SslMode.disable : SslMode.require,
    ),
  );
}
