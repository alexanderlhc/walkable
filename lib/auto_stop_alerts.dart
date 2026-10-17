/// How the recorder tells a walker, outside the app, that auto-stop is about
/// to end their walk, and that it has. Injected into [WalkRecorder] like the
/// location service: the composition root supplies the system-notification
/// adapter, and tests a fake that records the calls.
///
/// Alerts are best-effort: a walker who denied notifications simply gets
/// none, and auto-stop works the same.
abstract interface class AutoStopAlerts {
  /// Shows the "Still walking?" warning with its Keep walking / Stop now
  /// choice; the walk stops itself after [timeLeft] more moving time.
  Future<void> showWarning(Duration timeLeft);

  /// Withdraws the warning: the walker answered it, or the walk paused or
  /// ended.
  Future<void> cancelWarning();

  /// Shows that the walk stopped itself and was saved, in place of the
  /// warning.
  Future<void> showStoppedNotice();
}

/// Shows nothing. The recorder's default, for when no alerts are wired up.
class NoAutoStopAlerts implements AutoStopAlerts {
  const NoAutoStopAlerts();

  @override
  Future<void> showWarning(Duration timeLeft) async {}

  @override
  Future<void> cancelWarning() async {}

  @override
  Future<void> showStoppedNotice() async {}
}
