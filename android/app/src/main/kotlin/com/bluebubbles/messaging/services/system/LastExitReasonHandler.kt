package com.bluebubbles.messaging.services.system

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.util.Log
import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.models.MethodCallHandlerImpl
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * TEMPORARY startup-diag helper — reports why the *previous* app process died,
 * using Android's ApplicationExitInfo (API 30+). A native crash / ANR / OOM kill
 * runs no Dart code, so StartupDiag can only tell that the last session ended
 * uncleanly, not *why*. This lets it name the cause (native signal vs ANR vs
 * low-memory vs user-swipe) from the pullable in-app log, without adb/logcat.
 *
 * TO REMOVE with the rest of the startup-diag instrumentation (grep `[startup-diag]`).
 */
class LastExitReasonHandler : MethodCallHandlerImpl() {
    companion object {
        const val tag = "get-last-exit-reason"
    }

    override fun handleMethodCall(call: MethodCall, result: MethodChannel.Result, context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success(null)
            return
        }
        try {
            val am = context.getSystemService(ActivityManager::class.java)
            val infos = am.getHistoricalProcessExitReasons(context.packageName, 0, 1)
            if (infos.isNullOrEmpty()) {
                result.success(null)
                return
            }
            val info = infos[0]
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
            result.success(map)
        } catch (e: Exception) {
            Log.e(Constants.logTag, "Failed to read last exit reason", e)
            result.success(null)
        }
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
