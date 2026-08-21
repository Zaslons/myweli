import 'dart:async';
import 'dart:io';

/// One build per minute, per process.
///
/// **Denial of wallet is the risk this bounds** (BACKEND.md §7 T68): builds cost
/// money, and a suspend/restore loop would otherwise trigger one each time. A
/// dropped event is safe — the next build reads the listable set fresh, so it
/// picks up everything that happened during the window.
const Duration kRebuildCooldown = Duration(seconds: 60);

/// Asks the web host to rebuild, because the set of publicly listable salons
/// changed.
///
/// The web's `/[slug]` route sets `dynamicParams = false` — the only thing that
/// makes Next serve a real 404 in the HTML rather than a 44-character shell —
/// so its slug set is fixed at BUILD time. Without this, a salon that becomes
/// listable after the last build 404s until the next one.
/// Design: docs/design/backend-web-rebuild-hook.md
abstract interface class SiteRebuildNotifier {
  /// Never throws and never blocks the caller's outcome. [reason] is for the
  /// log only.
  Future<void> requestRebuild(String reason);
}

/// The default. Wired whenever `WEB_DEPLOY_HOOK_URL` is unset — dev, CI, and
/// any self-hosted run — so absent configuration changes nothing.
class NoopSiteRebuildNotifier implements SiteRebuildNotifier {
  @override
  Future<void> requestRebuild(String reason) async {}
}

/// POSTs an empty body to a Vercel Deploy Hook.
class HttpSiteRebuildNotifier implements SiteRebuildNotifier {
  HttpSiteRebuildNotifier(
    this._hookUrl, {
    HttpClient? client,
    DateTime Function()? clock,
    Duration cooldown = kRebuildCooldown,
    void Function(String)? log,
  }) : _client = client ?? HttpClient(),
       _clock = clock ?? DateTime.now,
       _cooldown = cooldown,
       _log = log ?? print;

  final Uri _hookUrl;
  final HttpClient _client;
  final DateTime Function() _clock;
  final Duration _cooldown;
  final void Function(String) _log;
  DateTime? _lastFired;

  @override
  Future<void> requestRebuild(String reason) async {
    final now = _clock().toUtc();
    final last = _lastFired;
    if (last != null && now.difference(last) < _cooldown) {
      _log('site_rebuild skipped reason=$reason cause=cooldown');
      return;
    }
    _lastFired = now;
    try {
      final req = await _client.postUrl(_hookUrl);
      req.headers.contentType = ContentType.json;
      req.write('{}');
      final res = await req.close();
      await res.drain<void>();
      // **The URL is a secret** — anyone holding it can trigger unlimited
      // builds — so the reason and the status are logged and the URL never is.
      _log('site_rebuild sent reason=$reason status=${res.statusCode}');
    } catch (e) {
      // **Fails open, loudly.** The write that triggered this already
      // succeeded; refusing a correct admin action because Vercel could not be
      // reached would be a self-inflicted outage. The residual is written down
      // in the design doc: the salon's page 404s until the next deploy.
      _log('site_rebuild FAILED reason=$reason error=$e');
    }
  }
}
