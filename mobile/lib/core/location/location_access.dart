import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_clock.dart';
import '../utils/logger.dart';

/// The phone's location, asked one way in the whole app.
///
/// Design: docs/design/consumer-location.md (A6, decisions 272–276), §5.
///
/// Three places use the position — the client map, « Près de moi » in the
/// shared commune picker, and MyWeli Pro's « Utiliser ma position » — and each
/// carried its own copy of the same flow, unbounded in time, with no way to
/// the Settings after a refusal. They call this instead, and keep their own
/// words (§2).
///
/// It sits on [GeolocatorPlatform.instance], so a test answers the plugin's
/// channel (`flutter.baseflow.com/geolocator`) as the map tests already do.
/// It is not a `*ServiceInterface`: it reaches no server, and the position
/// never leaves the phone (§0, §6).
///
/// What the plugin says, read in its source (§0):
/// - **Android's `checkPermission` never says « refused for good »**: never
///   asked, refused once and refused for good all answer `denied`. Only
///   `requestPermission` tells them apart, answering `deniedForever` at once,
///   with no dialog, when no rationale is left (`PermissionManager.java:168-188`).
/// - **iOS answers `deniedForever` from the first refusal**, and `denied` for
///   a phone where location is restricted (Screen Time, a profile) as well as
///   for « not decided ». `requestPermission` returns at once unless iOS has
///   never asked (`PermissionHandler.m:47-50`), so a `denied` that survives a
///   request means **restricted** (`AuthorizationStatusMapper.m:13-17`).
/// - **One read at a time**: a second `requestPermission` on Android replaces
///   the first's callback, which then never answers; on iOS a second read
///   replaces the first's handler (§2.4). So [locate] is single, app-wide.
class LocationAccess {
  LocationAccess._();

  /// The app's one instance: the single-read rule is app-wide.
  static final LocationAccess instance = LocationAccess._();

  /// Every position read gives up after this (§2.1, decision 275). It covers
  /// Google's own « turn on location » dialog when the read opens it
  /// (`FusedLocationClient.java:236-257`); the person's answer to the
  /// PERMISSION dialog is not timed.
  static const Duration bound = Duration(seconds: 30);

  /// The permission dialog's own limit — generous, it is the person's
  /// answer. It exists for the request that never answers: Android drops the
  /// callback when the result comes back empty, « when the user cancels the
  /// permission request » (`PermissionManager.java:148-153`), and with one
  /// read app-wide, every location button would wait with it until the app
  /// restarts (independent review, 2026-11-27).
  static const Duration permissionBound = Duration(minutes: 2);

  /// How old a cached position may be and still be shown on opening the map
  /// ([recent]).
  static const Duration recentAge = Duration(minutes: 15);

  /// `SharedPreferences`: the map's ask banner was answered (§4).
  static const String explainedKey = 'location_explained';

  Future<LocationOutcome>? _running;

  GeolocatorPlatform get _platform => GeolocatorPlatform.instance;

  /// What the phone already allows. **No dialog, never throws**: the
  /// location service first, then the permission. A plugin that fails or
  /// answers nothing is [LocationStatus.unknown] — the plugin's own
  /// `checkPermission` throws on a `null` answer
  /// (`method_channel_geolocator.dart:40-43`).
  ///
  /// It never sets the « explained » flag: reading is not the person asking.
  Future<LocationStatus> status() async {
    try {
      if (!await _platform.isLocationServiceEnabled()) {
        return LocationStatus.off;
      }
      return switch (await _platform.checkPermission()) {
        LocationPermission.whileInUse ||
        LocationPermission.always => LocationStatus.allowed,
        LocationPermission.denied => LocationStatus.undecided,
        LocationPermission.deniedForever => LocationStatus.blocked,
        LocationPermission.unableToDetermine => LocationStatus.unknown,
      };
    } catch (e) {
      AppLogger.warning('Location status unreadable: ${e.runtimeType}');
      return LocationStatus.unknown;
    }
  }

  /// The position, asking first when the phone still can. Bounded by
  /// [bound]; never throws.
  ///
  /// [ask] `false` reads only what is already allowed, and never opens the
  /// dialog: the map's silent read on opening (§2.1). Every other call is a
  /// tap, which records that the person was asked (§4) — whatever comes of
  /// it.
  ///
  /// **One read at a time, app-wide**: a call while one runs gets the one
  /// running.
  Future<LocationOutcome> locate({
    required LocationAccuracy accuracy,
    bool ask = true,
  }) {
    final running = _running;
    if (running != null) return running;
    final read = _locate(accuracy, ask: ask);
    _running = read;
    return read.whenComplete(() {
      if (identical(_running, read)) _running = null;
    });
  }

  Future<LocationOutcome> _locate(
    LocationAccuracy accuracy, {
    required bool ask,
  }) async {
    if (ask) await markExplained();
    try {
      if (!await _platform.isLocationServiceEnabled()) {
        return const LocationOff();
      }
      var permission = await _platform.checkPermission();
      if (permission == LocationPermission.denied) {
        if (!ask) return const LocationRefused();
        permission = await _platform.requestPermission().timeout(
          permissionBound,
        );
        if (permission == LocationPermission.denied) {
          // iOS answers `denied` to a request only when it cannot show its
          // dialog at all: a restricted phone. Android: refused, and the
          // phone may ask again.
          return defaultTargetPlatform == TargetPlatform.iOS
              ? const LocationRestricted()
              : const LocationRefused();
        }
      }
      switch (permission) {
        case LocationPermission.deniedForever:
          return const LocationBlocked();
        case LocationPermission.denied:
        case LocationPermission.unableToDetermine:
          return const LocationFailed();
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          break;
      }
      final position = await _platform.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          // The plugin's own limit, not a `.timeout` around it: on Android it
          // also cancels the native request (`cancelGetCurrentPosition`),
          // which a timeout outside would leave running.
          timeLimit: bound,
        ),
      );
      return Located(position, approximate: await _approximate());
    } on LocationServiceDisabledException {
      // Location turned off during the read, or Google's « turn on
      // location » dialog refused (§2.4).
      return const LocationOff();
    } catch (e) {
      // A timeout, or the plugin's own (English) failure: the screens say
      // it in their words.
      AppLogger.warning('Location read failed: ${e.runtimeType}');
      return const LocationFailed();
    }
  }

  /// The phone's last position, when it is no older than [maxAge] — with no
  /// dialog of any kind and no read started. `null` otherwise, or on any
  /// failure.
  ///
  /// It is the map's silent read on Android: a read there can open Google's
  /// « turn on location » dialog when the phone's location settings do not
  /// meet the request (`FusedLocationClient.java:236-257`), and opening
  /// « Carte » never shows a dialog by itself (§2.1, decision 273). The last
  /// position is `getLastLocation()`, which checks no setting.
  Future<Located?> recent({Duration maxAge = recentAge}) async {
    try {
      final position = await _platform.getLastKnownPosition();
      if (position == null) return null;
      if (AppClock.now().difference(position.timestamp) > maxAge) return null;
      return Located(position, approximate: await _approximate());
    } catch (e) {
      AppLogger.warning('Last position unreadable: ${e.runtimeType}');
      return null;
    }
  }

  /// `true` when the phone gave an approximate position: the person chose
  /// « Approximative » (Android) or turned « Position exacte » off (iOS), or
  /// the app asks for no more (the client on Android, decision 272).
  /// Unreadable → `false`: say nothing rather than something wrong.
  Future<bool> _approximate() async {
    try {
      return await _platform.getLocationAccuracy() ==
          LocationAccuracyStatus.reduced;
    } catch (_) {
      return false;
    }
  }

  /// Whether the map's ask banner was answered, or the flow ran (§4).
  Future<bool> explained() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(explainedKey) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// « Plus tard », and the start of every [locate] that may ask.
  Future<void> markExplained() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(explainedKey, true);
    } catch (e) {
      AppLogger.warning('Could not record location_explained: $e');
    }
  }

  /// MyWeli's own page in the phone's Settings. Never throws; `false` when
  /// it did not open.
  Future<bool> openAppSettings() => _open(_platform.openAppSettings, 'app');

  /// The phone's location page on Android. On iOS an app can open only its
  /// own page, which cannot turn the service on (§2.1): callers offer it on
  /// Android only.
  Future<bool> openLocationSettings() =>
      _open(_platform.openLocationSettings, 'location');

  Future<bool> _open(Future<bool> Function() open, String which) async {
    try {
      return await open();
    } catch (e, s) {
      AppLogger.error(
        'Could not open the $which settings',
        error: e,
        stackTrace: s,
      );
      return false;
    }
  }

  /// Tests only: forget a read a test left running.
  @visibleForTesting
  void debugReset() => _running = null;
}

/// What the phone already allows, read with no dialog ([LocationAccess.status]).
enum LocationStatus {
  /// The app may read the position.
  allowed,

  /// The phone may still show its dialog — or, on Android, a refusal for good
  /// from before; on iOS, a restricted phone (§2.1). Only a request tells.
  undecided,

  /// Refused for good: only the Settings can allow it.
  blocked,

  /// The phone's location is turned off.
  off,

  /// The plugin failed or answered nothing.
  unknown,
}

/// The outcome of [LocationAccess.locate].
sealed class LocationOutcome {
  const LocationOutcome();
}

/// A position. [approximate]: the phone gave an approximate one.
final class Located extends LocationOutcome {
  const Located(this.position, {required this.approximate});

  final Position position;
  final bool approximate;
}

/// Refused; the phone may ask again (Android only).
final class LocationRefused extends LocationOutcome {
  const LocationRefused();
}

/// Refused for good: only the app's Settings page can allow it.
final class LocationBlocked extends LocationOutcome {
  const LocationBlocked();
}

/// iOS: location restricted on this phone (Screen Time, an installed
/// profile). Neither the dialog nor the app's Settings page can change it.
final class LocationRestricted extends LocationOutcome {
  const LocationRestricted();
}

/// The phone's location is turned off.
final class LocationOff extends LocationOutcome {
  const LocationOff();
}

/// No position within [LocationAccess.bound], or the plugin failed.
final class LocationFailed extends LocationOutcome {
  const LocationFailed();
}
