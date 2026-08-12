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
      maxConnectionCount: kMaxConnectionsPerInstance,
      sslMode: isLocal ? SslMode.disable : SslMode.require,
    ),
  );
}

/// Connections this process may hold — **per Cloud Run instance**, and that is
/// the whole point of the number.
///
/// It was 8, against a `db-f1-micro` whose `max_connections` default is **25**
/// with no flag override. `service.yaml` sets `maxScale: 4`, so four instances
/// could demand **32** — over the ceiling before anything went wrong. Worse, the
/// arithmetic understates it twice: Postgres reserves
/// `superuser_reserved_connections` (3), leaving **~22** for `myweli_app`; and
/// `maxScale` is **per revision**, so a rollout runs the draining old revision
/// alongside the new one and can transiently reach eight instances — **64**.
///
/// This was not theoretical headroom. Cloud Monitoring's 30-day peak on
/// `postgresql/num_backends` is **10 backends against a single instance** — one
/// instance already saturates a pool of 8. The second takes it to ~18, the third
/// past 25.
///
/// **4 × 4 = 16**, comfortably inside ~22, with room for the rollout overlap.
///
/// The obvious alternative — raising `max_connections` on the instance — was
/// rejected on evidence, not taste. The flag `requiresRestart: true` on a
/// `ZONAL` instance with no replica, and this app has **no connection retry**:
/// `main.dart` awaits `initializeDatabase()`, which takes an advisory lock, and
/// `connectTimeout` is a deadline rather than a grace period, so a restart can
/// kill revisions rather than merely stall them. And 100 backends at ~8 MB each
/// would need ~800 MB against the instance's **0.6 GB** — trading a connection
/// ceiling for an OOM. Details: docs/design/infra-staging.md §7.
///
/// Raise this only together with the instance tier, and recompute against
/// `maxScale` when either moves.
const int kMaxConnectionsPerInstance = 4;
