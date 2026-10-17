import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:walkable/auto_stop_alerts.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/walk_recorder.dart';

/// The production [AutoStopAlerts]: Android system notifications through
/// flutter_local_notifications, so the warning reaches a walker whose phone
/// is locked in a pocket.
///
/// A thin pass-through, checked by hand on a device rather than by tests.
/// Notifications are shown the moment the recorder's ticker asks, never
/// scheduled, so no exact-alarm permission is needed. They reuse the
/// notification permission requested when a walk starts: with it denied,
/// Android drops them silently and auto-stop works the same.
class AutoStopNotifications implements AutoStopAlerts {
  /// The current app strings, read at each show so the notifications follow
  /// the language setting.
  final AppLocalizations Function() _localizations;

  final FlutterLocalNotificationsPlugin _plugin;

  AutoStopNotifications({
    required AppLocalizations Function() localizations,
    FlutterLocalNotificationsPlugin? plugin,
  })  : _localizations = localizations,
        _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  // The warning and the notice share one id, so the notice takes the
  // warning's place and one cancel clears whichever is up.
  static const _notificationId = 26;
  static const _channelId = 'auto_stop';
  static const _keepWalkingAction = 'keep_walking';
  static const _stopNowAction = 'stop_now';

  /// Sets up the plugin and routes the warning's actions to [onKeepWalking]
  /// and [onStopNow] (the recorder's commands). Call once at startup, before
  /// the first walk.
  ///
  /// Also clears any auto-stop notification left by a process that died
  /// mid-walk: a fresh process has no walk for it to be about.
  Future<void> initialize({
    required VoidCallback onKeepWalking,
    required VoidCallback onStopNow,
  }) async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_walk'),
        ),
        // Both actions open the app, so their taps arrive here, in the main
        // isolate where the recorder lives. A tap on the body only opens the
        // app, where the in-app banner offers the same choice. An action
        // that cold-starts the app has no walk to act on, so launch details
        // are not consulted.
        onDidReceiveNotificationResponse: (response) {
          switch (response.actionId) {
            case _keepWalkingAction:
              onKeepWalking();
            case _stopNowAction:
              onStopNow();
          }
        },
      );
      await _plugin.cancel(id: _notificationId);
    } catch (e) {
      debugPrint('AutoStopNotifications: initialize failed: $e');
    }
  }

  @override
  Future<void> showWarning() {
    final l10n = _localizations();
    return _show(
      title: l10n.autoStopWarningTitle,
      body: l10n.autoStopWarningBody(WalkRecorder.autoStopGrace.inMinutes),
      // Stays until the walker answers or the recorder withdraws it, even if
      // they tap the body and leave the app without choosing.
      autoCancel: false,
      actions: [
        AndroidNotificationAction(_keepWalkingAction, l10n.actionKeepWalking,
            showsUserInterface: true),
        AndroidNotificationAction(_stopNowAction, l10n.actionStopNow,
            showsUserInterface: true),
      ],
    );
  }

  @override
  Future<void> cancelWarning() => _plugin.cancel(id: _notificationId);

  @override
  Future<void> showStoppedNotice() {
    final l10n = _localizations();
    return _show(
      title: l10n.autoStopNoticeTitle,
      body: l10n.autoStopNoticeBody,
      autoCancel: true,
    );
  }

  Future<void> _show({
    required String title,
    required String body,
    required bool autoCancel,
    List<AndroidNotificationAction>? actions,
  }) {
    final l10n = _localizations();
    return _plugin.show(
      id: _notificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        // Its own high-importance channel with the default sound and
        // vibration, so the walker can tune or mute it in Android's settings
        // without touching the recording notification.
        android: AndroidNotificationDetails(
          _channelId,
          l10n.autoStopChannelName,
          channelDescription: l10n.autoStopChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.public,
          autoCancel: autoCancel,
          actions: actions,
        ),
      ),
    );
  }
}
