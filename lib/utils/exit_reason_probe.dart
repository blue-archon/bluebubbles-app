import 'dart:async';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

/// [exit-reason-probe] Lightweight, standalone diagnostic.
///
/// On Android cold start, asks Android *why* the previous process died
/// (ApplicationExitInfo, API 30+) and logs it. A native crash / ANR / OOM kill
/// runs no Dart code, so this is the only in-app signal for the cause of the
/// resume->open-chat native kill (observation #2) without adb/logcat. The
/// record's reasonName + importance distinguish a foreground crash from a
/// background OOM reclaim.
///
/// Best-effort: never blocks or throws. Android-only (invokeMethod no-ops on
/// desktop/web). TO REMOVE once the native kill is resolved: delete this file,
/// its single call site in startup_tasks.dart, and LastExitReasonHandler.kt
/// (grep `exit-reason-probe`).
void reportPreviousExitReason() {
  try {
    if (kIsWeb || kIsDesktop) return;
    if (!GetIt.I.isRegistered<MethodChannelService>()) return;
    unawaited(() async {
      try {
        final info = await MethodChannelSvc.invokeMethod('get-last-exit-reason');
        Logger.warn('previous process exit reason: ${info ?? 'PROBE RETURNED NULL'}', tag: 'ExitReasonProbe');
      } catch (e) {
        Logger.warn('could not read exit reason: $e', tag: 'ExitReasonProbe');
      }
    }());
  } catch (_) {}
}
