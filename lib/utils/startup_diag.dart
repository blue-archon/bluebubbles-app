import 'dart:async';

import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:get_it/get_it.dart';

/// TEMPORARY startup / white-screen / native-kill diagnostic.
///
/// Purpose: a white screen is a startup *hang* (nothing rendered, no exception
/// thrown) or an async error that escapes the zone, and a native kill (observation
/// #2) runs no Dart code at all — so neither leaves a trace in the normal logs.
/// This records lightweight breadcrumbs + a durable "phase" marker so those
/// failures self-document in the pullable log without adb.
///
/// TO REMOVE once resolved: delete this file and every `// [startup-diag]` call
/// site (grep for that tag). Everything here is best-effort and must NEVER throw.
class StartupDiag {
  static const String _tag = 'StartupDiag';
  static const String _phaseKey = 'diag_last_phase';

  // ── Breadcrumb ring buffer (flushed at ERROR only on failure) ─────────────
  static final List<String> _crumbs = [];
  static bool _firstFrame = false;
  static Timer? _frameWatchdog;

  static void crumb(String stage) {
    try {
      _crumbs.add('${DateTime.now().toUtc().toIso8601String()} $stage');
      if (_crumbs.length > 60) _crumbs.removeAt(0);
      Logger.info('[crumb] $stage', tag: _tag);
    } catch (_) {}
  }

  /// Flush the whole breadcrumb trail at ERROR level so it survives error-only
  /// logging. Called by the watchdog and the async-error handlers.
  static void dump(String reason) {
    try {
      Logger.error('[$_tag] $reason\n  ${_crumbs.join('\n  ')}');
    } catch (_) {}
  }

  // ── White-screen hang watchdog ────────────────────────────────────────────
  // Armed early in startup; if no first frame renders within [timeout], dump
  // the trail. Runs on the event loop, so it fires for the common async-await
  // hang; it self-cancels the instant the first frame renders.
  static void armFirstFrameWatchdog({Duration timeout = const Duration(seconds: 15)}) {
    try {
      _frameWatchdog?.cancel();
      _frameWatchdog = Timer(timeout, () {
        if (_firstFrame) return;
        dump('WHITE SCREEN SUSPECTED: no first frame after ${timeout.inSeconds}s');
      });
    } catch (_) {}
  }

  static void markFirstFrame() {
    try {
      if (_firstFrame) return;
      _firstFrame = true;
      _frameWatchdog?.cancel();
      _frameWatchdog = null;
      crumb('ui:first-frame');
      recordPhase('running');
    } catch (_) {}
  }

  // ── Async error escape hatch (zone / PlatformDispatcher) ──────────────────
  static void reportUncaught(String source, Object error, StackTrace? stack) {
    try {
      dump('uncaught via $source');
      Logger.error('[$_tag] uncaught via $source', error: error, trace: stack);
    } catch (_) {}
  }

  // ── Durable phase marker (native-kill / observation #2) ───────────────────
  // Written to prefs on lifecycle transitions. A native kill leaves the last
  // phase behind, so the NEXT launch can report where the previous session died
  // even though nothing Dart-side ran at kill time. Best-effort persistence.
  static void recordPhase(String phase) {
    try {
      crumb('phase:$phase');
      if (!GetIt.I.isRegistered<SharedPreferencesService>()) return;
      // ignore: deprecated_member_use
      unawaited(PrefsSvc.i.setString(_phaseKey, '${DateTime.now().toUtc().toIso8601String()} $phase'));
    } catch (_) {}
  }

  /// Read the previous session's last phase and flag it if it died mid-work.
  /// `paused` == normal background (OS may reclaim; not flagged). Anything else
  /// (`starting` = white screen/startup hang, `resumed` = killed during a resume
  /// = observation #2, `running` = crashed while active) is logged at ERROR.
  static void checkPreviousSession() {
    try {
      if (!GetIt.I.isRegistered<SharedPreferencesService>()) return;
      // ignore: deprecated_member_use
      final last = PrefsSvc.i.getString(_phaseKey);
      if (last != null) {
        final normalBackground = last.contains('paused') || last.contains('clean');
        if (normalBackground) {
          Logger.info('[$_tag] previous session last phase: $last', tag: _tag);
        } else {
          Logger.error('[$_tag] previous session ended UNCLEANLY — last phase: $last');
        }
      }
      recordPhase('starting');
    } catch (_) {}
  }
}
