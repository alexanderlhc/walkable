/// How much moving time a walk may record before it stops and saves itself.
/// Moving time, not wall-clock time: paused time never counts. Auto-stop Off
/// is the absence of a limit (null), not a value of this enum.
///
/// Each walk keeps the limit it started with; see [WalkRecorder.start].
enum AutoStopLimit {
  oneHour(1),
  twoHours(2),
  fourHours(4);

  /// Whole hours: the settings labels and the summary note count in hours.
  final int hours;

  const AutoStopLimit(this.hours);

  Duration get duration => Duration(hours: hours);
}
