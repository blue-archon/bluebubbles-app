import 'dart:async';

import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// App-owned desktop notification abstraction.
///
/// It mirrors the small slice of the (now-removed) `local_notifier` API that
/// [NotificationsService] relied on — per-toast [onClick]/[onClickAction]/
/// [onInput]/[onClose] closures plus [show]/[close] — but is implemented on top
/// of the maintained, cross-platform `flutter_local_notifications`.
///
/// `flnp` uses a single global response callback keyed by payload, so this class
/// owns the id↔instance map and fans the central callback back out to the right
/// notification's closures. That keeps the intricate batching/avatar/routing
/// logic in [NotificationsService] untouched, and isolates the notification
/// backend behind one swappable file.
///
/// Platform notes:
/// - Linux: full support (actions, avatar icon, sound/suppress, urgency,
///   resident/never-timeout for the persistent FaceTime notif). D-Bus has no
///   inline reply, so [hasInput] is Windows/macOS-only (unchanged from before).
/// - Windows: full support incl. inline reply and a native looping ring
///   (`scenario: incomingCall`).
/// - macOS: basic support (title/body/sound/image). Action buttons on macOS
///   require statically-registered categories, so they are best-effort.
/// - `flnp` exposes no "dismissed" callback, so [onClose] only fires on explicit
///   [close]. FaceTime persistence is handled by the caller (resident notif +
///   looped ring audio); temp-file cleanup is done on a timer by the caller.
enum DesktopNotificationType { imageAndText02, imageAndText03, text02 }

enum DesktopNotificationSound { call, sms }

enum DesktopNotificationSoundOption { loop, silent, defaultOption }

enum DesktopNotificationDuration { short, long }

/// Kept for API compatibility with the previous close-reason handling. With
/// `flnp` only [closed] (explicit close) is ever reported.
enum DesktopNotificationCloseReason { unknown, timedOut, dismissed, closed }

class DesktopNotificationAction {
  const DesktopNotificationAction({required this.text});

  final String text;
}

class DesktopNotification {
  DesktopNotification({
    this.type = DesktopNotificationType.text02,
    this.imagePath,
    this.title,
    this.body,
    this.attributionText,
    this.duration = DesktopNotificationDuration.short,
    this.actions = const <DesktopNotificationAction>[],
    this.hasInput = false,
    this.inputPlaceholder,
    this.inputButtonText,
    this.systemSound,
    this.soundOption,
    this.persistent = false,
    this.showOpenAction = false,
  });

  final DesktopNotificationType type;
  final String? imagePath;
  final String? title;
  final String? body;
  final String? attributionText;
  final DesktopNotificationDuration duration;
  final List<DesktopNotificationAction> actions;
  final bool hasInput;
  final String? inputPlaceholder;
  final String? inputButtonText;
  final DesktopNotificationSound? systemSound;
  final DesktopNotificationSoundOption? soundOption;

  /// When true the notification stays until explicitly closed (used for the
  /// incoming-FaceTime notification). Maps to resident/never-timeout on Linux,
  /// `scenario: incomingCall` on Windows, and a critical interruption on macOS.
  final bool persistent;

  /// When true, an explicit "Open" action button (routed to [onClick]) is added.
  /// KDE Plasma doesn't deliver the default action on body-click, so this gives a
  /// reliable, consistent click-to-open button across Linux and Windows.
  final bool showOpenAction;

  // FutureOr so the service can assign either sync or async closures (it does both).
  FutureOr<void> Function()? onClick;
  FutureOr<void> Function(int index)? onClickAction;
  FutureOr<void> Function(String text)? onInput;
  FutureOr<void> Function(DesktopNotificationCloseReason reason)? onClose;

  int? _id;
  int? get id => _id;

  static const String _replyInputId = 'reply';
  static const String _openActionKey = 'open';

  /// The shared plugin instance + central callback are wired once by
  /// [NotificationsService.init] via [registerPlugin].
  static FlutterLocalNotificationsPlugin? _plugin;
  static final Map<int, DesktopNotification> _active = {};
  static int _idCounter = 1000;

  /// Wire the shared plugin so [show]/[close] and the central response router
  /// operate on the same instance the service already owns.
  static void registerPlugin(FlutterLocalNotificationsPlugin plugin) {
    _plugin = plugin;
  }

  /// Central `onDidReceiveNotificationResponse` handler. Routes a tap/action on
  /// any desktop notification back to that instance's closures.
  static void handleResponse(NotificationResponse response) {
    Logger.debug(
      'Desktop notif response: type=${response.notificationResponseType}, action=${response.actionId}, payload=${response.payload}',
      tag: 'DesktopNotification',
    );
    final int? id = int.tryParse(response.payload ?? '');
    if (id == null) return;
    final DesktopNotification? notif = _active[id];
    if (notif == null) return;

    switch (response.notificationResponseType) {
      case NotificationResponseType.selectedNotification:
        notif.onClick?.call();
        break;
      case NotificationResponseType.selectedNotificationAction:
        final String? input = response.input;
        final String? actionId = response.actionId;
        if (actionId == _openActionKey) {
          notif.onClick?.call();
        } else if (input != null && input.isNotEmpty && notif.hasInput) {
          notif.onInput?.call(input);
        } else {
          final int? index = int.tryParse(actionId ?? '');
          if (index != null) {
            notif.onClickAction?.call(index);
          } else {
            // 'default' (Linux body-click) or any non-numeric id -> treat as a tap.
            notif.onClick?.call();
          }
        }
        break;
    }
  }

  Future<void> show() async {
    final FlutterLocalNotificationsPlugin? plugin = _plugin;
    if (plugin == null) {
      Logger.warn('DesktopNotification.show called before registerPlugin', tag: 'DesktopNotification');
      return;
    }
    _id ??= _idCounter++;
    _active[_id!] = this;

    try {
      await plugin.show(
        id: _id!,
        title: title,
        body: _bodyWithAttribution,
        notificationDetails: NotificationDetails(
          linux: _linuxDetails,
          windows: _windowsDetails,
          macOS: _darwinDetails,
        ),
        payload: '$_id',
      );
    } catch (e, s) {
      Logger.error('Failed to show desktop notification', error: e, trace: s, tag: 'DesktopNotification');
    }
  }

  Future<void> close() async {
    final int? id = _id;
    if (id == null) return;
    _active.remove(id);
    try {
      await _plugin?.cancel(id: id);
    } catch (e, s) {
      Logger.error('Failed to close desktop notification', error: e, trace: s, tag: 'DesktopNotification');
    }
    await onClose?.call(DesktopNotificationCloseReason.closed);
  }

  String? get _bodyWithAttribution => attributionText != null ? '$attributionText$body' : body;

  bool get _linuxSuppressSound =>
      soundOption == DesktopNotificationSoundOption.silent || soundOption == DesktopNotificationSoundOption.loop;

  bool get _loop => soundOption == DesktopNotificationSoundOption.loop;

  WindowsNotificationSound get _windowsSound {
    if (_loop || systemSound == DesktopNotificationSound.call) return WindowsNotificationSound.call1;
    if (systemSound == DesktopNotificationSound.sms) return WindowsNotificationSound.sms;
    return WindowsNotificationSound.defaultSound;
  }

  // Freedesktop sound-theme name used for the Linux notification sound hint.
  String get _linuxSoundName =>
      systemSound == DesktopNotificationSound.call ? 'phone-incoming-call' : 'message-new-instant';

  // ----- Linux -----
  LinuxNotificationDetails get _linuxDetails => LinuxNotificationDetails(
        icon: imagePath != null ? FilePathLinuxIcon(imagePath!) : null,
        actions: [
          if (showOpenAction) const LinuxNotificationAction(key: _openActionKey, label: 'Open'),
          for (int i = 0; i < actions.length; i++) LinuxNotificationAction(key: '$i', label: actions[i].text),
        ],
        defaultActionName: 'default',
        sound: _linuxSuppressSound ? null : ThemeLinuxSound(_linuxSoundName),
        suppressSound: _linuxSuppressSound,
        urgency: persistent ? LinuxNotificationUrgency.critical : LinuxNotificationUrgency.normal,
        resident: persistent,
        timeout: persistent
            ? const LinuxNotificationTimeout.expiresNever()
            : const LinuxNotificationTimeout.systemDefault(),
      );

  // ----- Windows -----
  WindowsNotificationDetails get _windowsDetails => WindowsNotificationDetails(
        images: [
          if (imagePath != null) WindowsImage(Uri.file(imagePath!), altText: 'avatar'),
        ],
        inputs: [
          if (hasInput) WindowsTextInput(id: _replyInputId, placeHolderContent: inputPlaceholder),
        ],
        actions: [
          if (showOpenAction) const WindowsAction(content: 'Open', arguments: _openActionKey),
          if (hasInput && inputButtonText != null)
            WindowsAction(content: inputButtonText!, arguments: _replyInputId, inputId: _replyInputId),
          for (int i = 0; i < actions.length; i++) WindowsAction(content: actions[i].text, arguments: '$i'),
        ],
        scenario: persistent ? WindowsNotificationScenario.incomingCall : null,
        audio: soundOption == DesktopNotificationSoundOption.silent
            ? WindowsNotificationAudio.silent()
            : WindowsNotificationAudio.preset(sound: _windowsSound, shouldLoop: _loop),
      );

  // ----- macOS -----
  DarwinNotificationDetails get _darwinDetails => DarwinNotificationDetails(
        presentSound: soundOption != DesktopNotificationSoundOption.silent,
        attachments: imagePath != null ? [DarwinNotificationAttachment(imagePath!)] : null,
        interruptionLevel: persistent ? InterruptionLevel.critical : null,
      );
}
