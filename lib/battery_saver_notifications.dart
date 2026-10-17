import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:walkable/l10n/app_localizations.dart';

/// How the walk screen tells a walker whose phone is locked in a pocket that
/// Battery Saver started cutting location mid-walk — switched on by hand, or
/// automatically at low battery. Injected like [AutoStopAlerts]; tests use a
/// fake that records the calls.
///
/// Best-effort: with notifications denied the in-app warning is all there is.
abstract interface class BatterySaverAlerts {
  /// Shows the Battery Saver warning.
  Future<void> showWarning();

  /// Withdraws it: Battery Saver stopped restricting location, or the walk
  /// paused or ended.
  Future<void> cancelWarning();
}

/// Shows nothing. The default, for when no alerts are wired up.
class NoBatterySaverAlerts implements BatterySaverAlerts {
  const NoBatterySaverAlerts();

  @override
  Future<void> showWarning() async {}

  @override
  Future<void> cancelWarning() async {}
}

/// The production [BatterySaverAlerts]: an Android system notification
/// through flutter_local_notifications, which [AutoStopNotifications]
/// initializes at startup. A tap opens the app, where the in-app warning
/// offers the Battery Saver settings.
///
/// A thin pass-through, checked by hand on a device rather than by tests.
class BatterySaverNotifications implements BatterySaverAlerts {
  /// The current app strings, read at each show so the notification follows
  /// the language setting.
  final AppLocalizations Function() _localizations;

  final _plugin = FlutterLocalNotificationsPlugin();

  BatterySaverNotifications({
    required AppLocalizations Function() localizations,
  }) : _localizations = localizations;

  static const _notificationId = 45;
  static const _channelId = 'battery_saver';

  @override
  Future<void> showWarning() async {
    final l10n = _localizations();
    try {
      await _plugin.show(
        id: _notificationId,
        title: l10n.batterySaverNotificationTitle,
        body: l10n.batterySaverLocationWarning,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            l10n.batterySaverChannelName,
            channelDescription: l10n.batterySaverChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.public,
            // The warning is longer than one line.
            styleInformation:
                BigTextStyleInformation(l10n.batterySaverLocationWarning),
          ),
        ),
      );
    } catch (e) {
      debugPrint('BatterySaverNotifications: show failed: $e');
    }
  }

  @override
  Future<void> cancelWarning() async {
    try {
      await _plugin.cancel(id: _notificationId);
    } catch (e) {
      debugPrint('BatterySaverNotifications: cancel failed: $e');
    }
  }
}
