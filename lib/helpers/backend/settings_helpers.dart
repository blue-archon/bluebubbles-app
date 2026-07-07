import 'dart:convert';

import 'package:bluebubbles/helpers/backend/foreground_service_helpers.dart';
import 'package:bluebubbles/helpers/network/network_helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_io/io.dart';

/// Keys that native Kotlin (`SettingsHelper`) reads from the legacy
/// `FlutterSharedPreferences` XML.
const List<String> _nativeReadSettingKeys = [
  'serverAddress',
  'guidAuthKey',
  'apiTimeout',
  'customHeaders',
  'enablePrivateAPI',
  'privateAPISend',
  'privateAPIAttachmentSend',
  'notificationReactionAction',
  'notificationReactionActionType',
  'sendEventsToTasker',
];

/// Mirrors the settings that native code reads into the legacy
/// `FlutterSharedPreferences` store.
///
/// The Dart app persists settings to Android DataStore
/// (`SharedPreferencesWithCache`), but native services — the notification
/// tapback (`HttpService`/`SettingsHelper`), `SocketIOForegroundService`, and
/// Firebase auth — read the *legacy* XML, which DataStore does not write to.
/// Without this mirror they see an empty server URL / auth key (symptom:
/// notification "Like" fails with "No server URL configured"). Android-only;
/// no-op elsewhere. Best-effort — never throws.
Future<void> mirrorNativeSettingsToLegacyPrefs() async {
  if (kIsWeb) return;
  if (!Platform.isAndroid) return;
  try {
    final legacy = await SharedPreferences.getInstance();
    final map = SettingsSvc.settings.toMap();
    for (final key in _nativeReadSettingKeys) {
      if (!map.containsKey(key)) continue;
      final value = map[key];
      if (value is bool) {
        await legacy.setBool(key, value);
      } else if (value is int) {
        await legacy.setInt(key, value);
      } else if (value is double) {
        await legacy.setInt(key, value.toInt());
      } else if (value is String) {
        await legacy.setString(key, value);
      } else if (value != null) {
        // Maps/Lists (e.g. customHeaders) — JSON, matching native Gson parsing.
        await legacy.setString(key, jsonEncode(value));
      }
    }
  } catch (e, stack) {
    Logger.warn('Failed to mirror native settings to legacy prefs', error: e, trace: stack);
  }
}

Future<bool> saveNewServerUrl(String newServerUrl,
    {bool tryRestartForegroundService = true,
    bool restartSocket = true,
    bool force = false,
    List<String> saveAdditionalSettings = const []}) async {
  String sanitized = sanitizeServerAddress(address: newServerUrl)!;
  if (force || sanitized != SettingsSvc.settings.serverAddress.value) {
    SettingsSvc.settings.serverAddress.value = sanitized;

    await SettingsSvc.settings.saveManyAsync(["serverAddress", ...saveAdditionalSettings]);
    // Keep the legacy store (which native services read) in sync.
    await mirrorNativeSettingsToLegacyPrefs();

    // Don't await because we don't care about the result
    if (tryRestartForegroundService) {
      restartForegroundService();
    }

    try {
      if (restartSocket) {
        SocketSvc.restartSocket();
      }
    } catch (e, stack) {
      Logger.error("Failed to restart socket!", error: e, trace: stack);
    }

    return true;
  }

  return false;
}

Future<void> clearServerUrl(
    {bool tryRestartForegroundService = true, List<String> saveAdditionalSettings = const []}) async {
  SettingsSvc.settings.serverAddress.value = "";
  await SettingsSvc.settings.saveManyAsync(["serverAddress", ...saveAdditionalSettings]);
  await mirrorNativeSettingsToLegacyPrefs();

  // Don't await because we don't care about the result
  if (tryRestartForegroundService) {
    restartForegroundService();
  }
}

/// Prompts the user to disable battery optimizations for the app
///
/// Returns true if the user has disabled battery optimizations
Future<bool> disableBatteryOptimizations() async {
  bool? isDisabled = await DisableBatteryOptimization.isAllBatteryOptimizationDisabled;

  // If battery optomizations are already disabled, return true
  if (isDisabled == true) return true;

  // If optimizations are not disabled, prompt the user to disable them
  isDisabled = await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();
  return isDisabled ?? false;
}
