package com.bluebubbles.messaging.services.system

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.models.MethodCallHandlerImpl
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Reports why the *previous* app process died, using Android's ApplicationExitInfo
 * (API 30+). A native crash / ANR / OOM kill runs no Dart code, so the only in-app
 * signal for the resume->open-chat native kill (observation #2) is to ask the OS on
 * the next cold start. Names the cause (native signal vs ANR vs low-memory vs
 * user-swipe) from the pullable in-app log, without adb/logcat.
 *
 * TEMPORARY instrument — remove with its Dart trigger once the kill is resolved
 * (grep `exit-reason-probe`).
 */
class LastExitReasonHandler : MethodCallHandlerImpl() {
    companion object {
        const val tag = "get-last-exit-reason"

        /// Enough history to cover the probed death plus the sessions around it.
        private const val MAX_RECORDS = 5
    }

    override fun handleMethodCall(call: MethodCall, result: MethodChannel.Result, context: Context) {
        // Never reply with a bare null. A silent null is indistinguishable from a
        // probe that ran and found nothing, which is exactly how this instrument
        // failed to explain the 2026-07-15 foreground death: the Dart side logged
        // the outbound call and then nothing at all. Every path now says why.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success(mapOf("probe" to "unavailable: SDK ${Build.VERSION.SDK_INT} < 30"))
            return
        }
        // Platform-channel calls arrive on the main thread, but this probe hits binder
        // and, for native crashes / ANRs, reads tombstone files off disk — during app
        // startup, no less. Doing that inline would risk stalling the very main thread
        // whose stalls we are trying to diagnose. Collect off-thread, reply on the main
        // looper (MethodChannel.Result must be answered there).
        val appContext = context.applicationContext
        val mainHandler = Handler(Looper.getMainLooper())
        Thread({
            val reply = collect(appContext)
            mainHandler.post { result.success(reply) }
        }, "last-exit-reason-probe").start()
    }

    private fun collect(context: Context): Map<String, Any?> {
        return try {
            val am = context.getSystemService(ActivityManager::class.java)
                ?: return mapOf("probe" to "unavailable: no ActivityManager on this context")
            // Pull several records, not just the newest: the record for the death we
            // are asking about may not be written yet when we probe seconds later, and
            // the surrounding history tells us whether the process is dying at all (an
            // empty list means Android never recorded a process exit, which points at
            // an engine/Activity restart rather than a process kill).
            val infos = am.getHistoricalProcessExitReasons(context.packageName, 0, MAX_RECORDS)
            if (infos.isNullOrEmpty()) {
                return mapOf("probe" to "ran, but no exit records exist for ${context.packageName}")
            }
            mapOf(
                "probe" to "ok (${infos.size} record(s), sdk ${Build.VERSION.SDK_INT})",
                "records" to infos.map { describe(it) },
            )
        } catch (e: Exception) {
            Log.e(Constants.logTag, "Failed to read last exit reason", e)
            mapOf("probe" to "failed: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    private fun describe(info: ApplicationExitInfo): Map<String, Any?> {
        val map = HashMap<String, Any?>()
        map["reason"] = info.reason
        map["reasonName"] = reasonName(info.reason)
        map["description"] = info.description
        map["timestamp"] = info.timestamp
        map["importance"] = info.importance
        map["processName"] = info.processName
        map["status"] = info.status
        map["pss_kb"] = info.pss
        map["rss_kb"] = info.rss
        // For native crashes / ANRs, pull the head of the tombstone/ANR trace —
        // this is where the crashing native frames / blocked main thread show up.
        if (info.reason == ApplicationExitInfo.REASON_CRASH_NATIVE ||
            info.reason == ApplicationExitInfo.REASON_ANR) {
            map["trace"] = readTraceHead(info)
        }
        return map
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_ANR -> "ANR (main thread blocked)"
        ApplicationExitInfo.REASON_CRASH -> "CRASH (jvm/dart uncaught)"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE (native signal)"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
        ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY (OOM killer)"
        ApplicationExitInfo.REASON_OTHER -> "OTHER (usually system-forced)"
        ApplicationExitInfo.REASON_PACKAGE_STATE_CHANGE -> "PACKAGE_STATE_CHANGE"
        ApplicationExitInfo.REASON_PACKAGE_UPDATED -> "PACKAGE_UPDATED"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
        ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED (killed by signal)"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED (swiped from recents)"
        ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
        else -> "UNKNOWN($reason)"
    }

    private fun readTraceHead(info: ApplicationExitInfo): String? {
        return try {
            info.traceInputStream?.bufferedReader()?.use { reader ->
                val sb = StringBuilder()
                var lines = 0
                for (line in reader.lineSequence()) {
                    sb.append(line).append('\n')
                    if (++lines >= 60) break
                }
                sb.toString()
            }
        } catch (e: Exception) {
            null
        }
    }
}
