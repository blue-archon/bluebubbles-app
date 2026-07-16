import 'dart:async';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
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
      // Ring buffer only — routine crumbs are silent. The trail is flushed at
      // ERROR by [dump] on an actual failure (white screen / uncaught error).
      _crumbs.add('${DateTime.now().toUtc().toIso8601String()} $stage');
      if (_crumbs.length > 60) _crumbs.removeAt(0);
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
        // Stay silent on a normal (paused/clean) previous session; only speak up
        // when the previous session died mid-work — observation #2 forensics.
        if (!normalBackground) {
          Logger.error('[$_tag] previous session ended UNCLEANLY — last phase: $last');
          _reportPreviousExitReason();
        }
      }
      recordPhase('starting');
    } catch (_) {}
  }

  /// Ask Android *why* the previous process died (ApplicationExitInfo, API 30+):
  /// native crash vs ANR vs OOM vs user-swipe. A native/native-kill death runs no
  /// Dart code, so this is the only in-app signal for the cause. Best-effort/async;
  /// never blocks or throws. Android-only (invokeMethod no-ops on desktop/web).
  static void _reportPreviousExitReason() {
    try {
      // Android-only. ApplicationExitInfo has no desktop equivalent, and
      // invokeMethod returns null on desktop/web without ever reaching Kotlin —
      // which the unconditional log below would misreport as a failed probe on
      // every unclean desktop exit.
      if (kIsWeb || kIsDesktop) return;
      if (!GetIt.I.isRegistered<MethodChannelService>()) return;
      unawaited(() async {
        try {
          // Log unconditionally. A null reply used to log nothing at all, so a
          // probe that silently found nothing looked identical to one that never
          // ran — the failure mode that cost us the 2026-07-15 crash cause.
          final info = await MethodChannelSvc.invokeMethod('get-last-exit-reason');
          Logger.error('[$_tag] previous process exit reason: ${info ?? 'PROBE RETURNED NULL'}');
        } catch (e) {
          Logger.warn('[$_tag] could not read exit reason: $e', tag: _tag);
        }
      }());
    } catch (_) {}
  }
}
