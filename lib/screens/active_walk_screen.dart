import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/screens/settings_screen.dart';
import 'package:walkable/screens/walk_detail_screen.dart';
import 'package:walkable/screens/walk_history_screen.dart';
import 'package:walkable/settings_controller.dart';
import 'package:walkable/theme.dart';
import 'package:walkable/units.dart';
import 'package:walkable/walk_recorder.dart';
import 'package:walkable/walk_stats.dart';

class ActiveWalkScreen extends StatefulWidget {
  final WalkRecorder recorder;
  final WalkRepository repository;
  final SettingsController settingsController;

  /// How many orphaned walks startup crash recovery salvaged into the
  /// history. When positive, the screen shows a one-time snackbar so the
  /// user knows why an interrupted walk reappeared.
  final int recoveredWalkCount;

  /// Presents the platform share sheet for a plain-text summary. Injectable
  /// so widget tests can observe the share without hitting the real platform
  /// channel; production uses the share_plus sheet.
  final Future<void> Function(String text) shareText;

  const ActiveWalkScreen({
    super.key,
    required this.recorder,
    required this.repository,
    required this.settingsController,
    this.recoveredWalkCount = 0,
    this.shareText = _systemShareSheet,
  });

  static Future<void> _systemShareSheet(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  State<ActiveWalkScreen> createState() => _ActiveWalkScreenState();
}

class _ActiveWalkScreenState extends State<ActiveWalkScreen> {
  WalkSnapshot? _snapshot;
  late RecorderState _recorderState;
  late StreamSubscription<WalkSnapshot> _sub;
  final MapController _mapController = MapController();
  bool _locationPermissionGranted = false;
  bool _recentring = false;
  LatLng? _currentPosition;
  StreamSubscription<Position>? _positionSub;

  // Height of the bottom panel, reported by it after layout. The panel overlays
  // the lower part of the map, so the camera treats that band as off-screen.
  double _bottomPanelHeight = 0;

  // The walk that just finished, as saved by [WalkRecorder.stop]. Non-null
  // while the post-walk summary panel is on screen: the map keeps drawing this
  // walk's route (reset() cleared the live snapshot's polyline) with
  // start/finish markers, and the panel shows its final stats. Cleared when
  // the user taps Done.
  Walk? _completedWalk;

  // One-shot auto-centre: when GPS goes from no-signal to its first fix, move
  // the camera onto the user once. Deliberately NOT sticky — we don't re-centre
  // on later updates (that would hijack the camera and fight the user panning),
  // and we don't re-centre after a signal loss/regain. The manual recentre chip
  // covers those cases.
  bool _hasAutoCentered = false;

  // Centre the camera on the first acquired fix, once. Guards camera access the
  // same way [_positionOutOfView] does: if the map isn't laid out yet the move
  // throws, and we leave [_hasAutoCentered] false so a later fix retries.
  void _maybeAutoCentre(LatLng position) {
    if (_hasAutoCentered) return;
    try {
      _mapController.move(position, _mapController.camera.zoom);
      _hasAutoCentered = true;
    } catch (_) {
      // Map not ready; retry on the next fix.
    }
  }

  // Whether the dot needs the recentre chip. Projects it to screen pixels and
  // checks it against the map inset by a grace margin — wider at the bottom,
  // where the panel hides the map. Without the grace the chip only appears once
  // the dot has fully left the map; a dot merely tucked behind the panel (still
  // inside the camera bounds) would otherwise stay hidden with no way back.
  bool get _positionOutOfView {
    final position = _currentPosition;
    if (position == null) return false;
    try {
      final camera = _mapController.camera;
      final offset = camera.latLngToScreenOffset(position);
      final size = camera.nonRotatedSize;
      const grace = 48.0;
      return offset.dx < grace ||
          offset.dy < grace ||
          offset.dx > size.width - grace ||
          offset.dy > size.height - _bottomPanelHeight - grace;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _recorderState = widget.recorder.state;
    _sub = widget.recorder.snapshots.listen((snapshot) {
      final last = snapshot.polyline.lastOrNull;
      setState(() {
        _snapshot = snapshot;
        _recorderState = widget.recorder.state;
        if (last != null) _currentPosition = LatLng(last.lat, last.lng);
      });
      if (last != null) _maybeAutoCentre(LatLng(last.lat, last.lng));
    });
    // Deferred to after the first frame: the foreground-location disclosure
    // dialog needs localizations and a Navigator, neither of which are
    // available synchronously in initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _requestPermission();
    });
    // Announce startup crash recovery once, after the first frame so a
    // ScaffoldMessenger (and localizations) are available.
    if (widget.recoveredWalkCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!
                .walksRecovered(widget.recoveredWalkCount)),
          ),
        );
      });
    }
  }

  Future<void> _requestPermission() async {
    final granted =
        await widget.recorder.locationService.checkAndRequestPermission(
      foregroundConsent: _showForegroundLocationDisclosure,
    );
    if (!mounted) return;
    setState(() => _locationPermissionGranted = granted);
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.locationPermissionDenied),
        ),
      );
      return;
    }
    _startLivePreview();
  }

  // Subscribes the pre-recording live-preview location stream that drives the
  // blue dot (and one-shot auto-centre) while the walk hasn't started yet. Must
  // not run concurrently with recording: geolocator keeps a single cached
  // position stream, so a live preview would shadow the recorder's foreground
  // stream (see [_onStart]). Cancels any existing preview first so it's safe to
  // call again when returning to idle after a walk.
  void _startLivePreview() {
    _positionSub?.cancel();
    _positionSub =
        widget.recorder.locationService.watchPosition().listen((pos) {
      if (!mounted) return;
      final latlng = LatLng(pos.latitude, pos.longitude);
      setState(() => _currentPosition = latlng);
      _maybeAutoCentre(latlng);
    }, onError: (Object e) {
      // Preview only drives the blue dot; log rather than let e.g. a
      // LocationServiceDisabledException surface as an unhandled async error.
      debugPrint('ActiveWalkScreen: live preview position error: $e');
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _positionSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _onRecentre() async {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, _mapController.camera.zoom);
      return;
    }
    setState(() => _recentring = true);
    try {
      final pos = await widget.recorder.locationService.getCurrentPosition();
      if (!mounted) return;
      final latlng = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _currentPosition = latlng;
        _recentring = false;
      });
      _mapController.move(latlng, _mapController.camera.zoom);
    } catch (e) {
      if (!mounted) return;
      setState(() => _recentring = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.locationError('$e'))),
      );
    }
  }

  /// Google Play "Prominent Disclosure": before the *initial* OS location
  /// prompt, explain that Walkable collects location data and why, and require
  /// the user to affirmatively accept. Returning `false` (declined) skips the
  /// OS prompt entirely; the map just shows without the live position.
  Future<bool> _showForegroundLocationDisclosure() async {
    if (!mounted) return false;
    final l10n = AppLocalizations.of(context)!;
    return _showDisclosureDialog(
      title: l10n.foregroundDisclosureTitle,
      body: l10n.foregroundDisclosureBody,
    );
  }

  /// Google Play "Prominent Disclosure": before the OS "Allow all the time"
  /// prompt, explain that Walkable collects location in the background — even
  /// with the app closed or the screen off — and why, and require the user to
  /// affirmatively accept. Returning `false` (declined or dismissed) skips the
  /// background prompt; the walk still records while the app is in use.
  Future<bool> _showBackgroundLocationDisclosure() async {
    if (!mounted) return false;
    final l10n = AppLocalizations.of(context)!;
    return _showDisclosureDialog(
      title: l10n.locationDisclosureTitle,
      body: l10n.locationDisclosureBody,
    );
  }

  Future<bool> _showDisclosureDialog({
    required String title,
    required String body,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.locationDisclosureDecline),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.locationDisclosureAccept),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  Future<void> _onStart() async {
    final l10n = AppLocalizations.of(context)!;
    // Tear down the live-preview location stream before recording starts.
    // geolocator keeps a single cached position stream and ignores the
    // locationSettings of any later getPositionStream() call while one is
    // active — so if the preview (plain settings) stays subscribed, the
    // recorder's foreground stream is shadowed: no notification and GPS gets
    // throttled once the screen locks. Cancelling synchronously clears
    // geolocator's cached stream (its asBroadcastStream onCancel runs during
    // cancel()), so the recorder's foreground stream is created fresh below.
    // Not awaited: the cache-clearing is synchronous, and awaiting a cancel
    // stalls under the widget-test fake clock. During recording the live dot is
    // driven by the recorder's snapshots stream instead.
    unawaited(_positionSub?.cancel());
    _positionSub = null;
    final result = await widget.recorder.start(
      notification: ForegroundNotificationText(
        title: l10n.notificationTitle,
        body: l10n.notificationText,
      ),
      foregroundConsent: _showForegroundLocationDisclosure,
      backgroundConsent: _showBackgroundLocationDisclosure,
    );
    if (!mounted) return;
    if (result == LocationServiceResult.permissionDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.locationPermissionDenied),
        ),
      );
      return;
    }
    setState(() {
      _recorderState = RecorderState.recording;
      // recorder.start() re-ran the permission check and it succeeded; keep
      // the flag in sync so the post-walk live preview (see [_onStop]) and the
      // recentre chip work even when the initial launch request was denied.
      _locationPermissionGranted = true;
    });
    if (!widget.recorder.locationService.notificationsGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.backgroundTrackingWarning),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: l10n.openSettings,
            onPressed: widget.recorder.locationService.openSettings,
          ),
        ),
      );
    }
    if (!widget.recorder.locationService.batteryOptimizationGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.batteryOptimizationWarning),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: l10n.openSettings,
            onPressed: widget.recorder.locationService.openSettings,
          ),
        ),
      );
    }
  }

  Future<void> _onPause() async {
    await widget.recorder.pause();
    if (!mounted) return;
    setState(() => _recorderState = RecorderState.paused);
  }

  Future<void> _onResume() async {
    await widget.recorder
        .resume(foregroundConsent: _showForegroundLocationDisclosure);
    if (!mounted) return;
    // Reflect the recorder's actual state: resume() stays paused when the
    // location permission was revoked in the meantime.
    setState(() => _recorderState = widget.recorder.state);
  }

  Future<void> _onStop() async {
    final walk = await widget.recorder.stop();
    widget.recorder.reset();
    if (!mounted) return;
    setState(() {
      _recorderState = RecorderState.idle;
      // Null (nothing recorded, or the save failed) skips the summary and
      // falls straight back to idle — there is no saved walk to present.
      _completedWalk = walk;
    });
    if (walk != null) {
      // Fit the camera to the finished route once the summary panel has laid
      // out AND reported its (taller) height — that takes one frame to render
      // the panel plus one for onHeightChanged's setState, hence two hops.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitCompletedRoute();
        });
      });
    }
    // Recording tore down the live preview (see [_onStart]); restart it so the
    // blue dot keeps following the user on the idle screen after the walk ends.
    if (_locationPermissionGranted) _startLivePreview();
  }

  // Move the camera so the whole finished route sits in view above the summary
  // panel, with the panel band treated as off-screen like everywhere else.
  void _fitCompletedRoute() {
    final points = _completedRoutePoints;
    if (points.length < 2) return;
    final bounds = LatLngBounds.fromPoints(points);
    // Zero-size bounds (every fix on one spot) can't be zoom-fit; leave the
    // camera where it is — the route is a dot the user is standing on anyway.
    if (bounds.north == bounds.south && bounds.east == bounds.west) return;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: EdgeInsets.fromLTRB(48, 100, 48, _bottomPanelHeight + 48),
        ),
      );
    } catch (_) {
      // Map not laid out yet; the summary still shows, just unfitted.
    }
  }

  /// The finished walk's route, or empty while no summary is showing.
  List<LatLng> get _completedRoutePoints =>
      _completedWalk?.coordinates.map((c) => LatLng(c.lat, c.lng)).toList() ??
      const [];

  void _dismissCompleted() {
    setState(() => _completedWalk = null);
  }

  void _viewCompletedRoute() {
    final walk = _completedWalk;
    if (walk == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WalkDetailScreen(
          walk: walk,
          settingsController: widget.settingsController,
        ),
      ),
    );
  }

  Future<void> _shareCompletedWalk() async {
    final walk = _completedWalk;
    if (walk == null) return;
    final l10n = AppLocalizations.of(context)!;
    final stats = WalkStats.of(walk);
    final units = _units;
    final distance = units == UnitSystem.metric
        ? l10n.unitKm(stats.formattedDistance(units))
        : l10n.unitMi(stats.formattedDistance(units));
    await widget.shareText(l10n.shareWalkSummary(
      distance,
      stats.formattedDuration(fallback: l10n.durationUnavailable),
    ));
  }

  UnitSystem get _units =>
      widget.settingsController.unitsOverride ??
      unitSystemForLocale(WidgetsBinding.instance.platformDispatcher.locale);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // While the post-walk summary is up, draw the saved walk's route (reset()
    // cleared the live snapshot's polyline); otherwise the live track.
    final completedPoints = _completedRoutePoints;
    final points = _completedWalk != null
        ? completedPoints
        : _snapshot?.polyline.map((c) => LatLng(c.lat, c.lng)).toList() ?? [];
    final units = _units;

    final topPadding = MediaQuery.of(context).padding.top + 12;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(55.6761, 12.5683),
              initialZoom: 17,
              onPositionChanged: (_, __) => setState(() {}),
            ),
            children: [
              TileLayer(
                urlTemplate: mapTileUrl(Theme.of(context).brightness),
                subdomains: mapTileSubdomains,
                userAgentPackageName: 'dk.alexanderlhc.walkable',
              ),
              if (points.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: points,
                      strokeWidth: 4,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              // The live dot is suppressed while the summary shows, for the
              // same reason as the re-centre chip below: the camera is on the
              // route, and the dot sits on the last fix where it swallows the
              // finish marker.
              if (_completedWalk == null && _currentPosition != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _currentPosition!,
                      radius: 8,
                      color: Theme.of(context).colorScheme.primary,
                      borderStrokeWidth: 2,
                      borderColor: Theme.of(context).colorScheme.surface,
                    ),
                  ],
                ),
              if (completedPoints.length >= 2)
                MarkerLayer(
                  markers: [
                    _routeEndMarker(
                      completedPoints.first,
                      l10n.markerStart.toUpperCase(),
                      WalkStatusColors.of(context).recording,
                    ),
                    _routeEndMarker(
                      completedPoints.last,
                      l10n.markerFinish.toUpperCase(),
                      Theme.of(context).colorScheme.error,
                    ),
                  ],
                ),
            ],
          ),
          _BottomPanel(
            state: _recorderState,
            snapshot: _snapshot,
            units: units,
            completedWalk: _completedWalk,
            onDismissCompleted: _dismissCompleted,
            onViewRoute: _viewCompletedRoute,
            onShare: _shareCompletedWalk,
            onStart: _onStart,
            onPause: _onPause,
            onResume: _onResume,
            onStop: _onStop,
            onHeightChanged: (height) {
              if (mounted && height != _bottomPanelHeight) {
                setState(() => _bottomPanelHeight = height);
              }
            },
          ),
          // Menu pill — top left. History and Settings live in here so the
          // map stays as empty as possible.
          Positioned(
            top: topPadding,
            left: 12,
            child: MenuAnchor(
              builder: (context, menu, _) => _MapChip(
                key: const Key('menu_button'),
                onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                semanticLabel: l10n.navMenu,
                icon: const Icon(Icons.menu, size: 18),
              ),
              menuChildren: [
                MenuItemButton(
                  key: const Key('history_button'),
                  leadingIcon: const Icon(Icons.history),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WalkHistoryScreen(
                        repository: widget.repository,
                        settingsController: widget.settingsController,
                      ),
                    ),
                  ),
                  child: Text(l10n.navHistory),
                ),
                MenuItemButton(
                  key: const Key('settings_button'),
                  leadingIcon: const Icon(Icons.settings),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        controller: widget.settingsController,
                      ),
                    ),
                  ),
                  child: Text(l10n.screenSettings),
                ),
              ],
            ),
          ),
          // Re-centre — top right, only when dot is off-screen. Suppressed
          // while the summary shows: the camera is deliberately on the route,
          // not the user, so the chip would be pure noise there.
          if (_completedWalk == null &&
              _locationPermissionGranted &&
              _positionOutOfView)
            Positioned(
              top: topPadding,
              right: 12,
              child: _MapChip(
                key: const Key('recenter_button'),
                onPressed: _recentring ? null : _onRecentre,
                semanticLabel: l10n.actionRecenter,
                icon: _recentring
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  // A labeled route-end marker: the dot sits on the route point, the label
  // chip hangs just below it.
  Marker _routeEndMarker(LatLng point, String label, Color color) {
    final cs = Theme.of(context).colorScheme;
    // The box anchors its top edge on the point (alignment below), so the dot
    // sits exactly on the route end; the height just reserves room for the
    // label chip hanging under it (with slack for larger text scales).
    return Marker(
      point: point,
      width: 72,
      height: 56,
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: cs.surface, width: 2.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: cs.inverseSurface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: cs.onInverseSurface,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom control panel ────────────────────────────────────────────────────
// Single frosted-glass surface that owns both stats and controls.
// Nothing outside this widget touches the bottom of the screen.

class _BottomPanel extends StatefulWidget {
  final RecorderState state;
  final WalkSnapshot? snapshot;
  final UnitSystem units;

  // When non-null (and the recorder is idle), the panel shows the "walk
  // complete" summary for this walk instead of the Start button.
  final Walk? completedWalk;
  final VoidCallback onDismissCompleted;
  final VoidCallback onViewRoute;
  final VoidCallback onShare;

  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  // Reports the panel's rendered height so the map can treat the area it covers
  // as off-screen when deciding whether to surface the recentre chip.
  final ValueChanged<double> onHeightChanged;

  const _BottomPanel({
    required this.state,
    required this.snapshot,
    required this.units,
    required this.completedWalk,
    required this.onDismissCompleted,
    required this.onViewRoute,
    required this.onShare,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onHeightChanged,
  });

  @override
  State<_BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<_BottomPanel> {
  // While true, the controls row is replaced by a Cancel / Finish confirmation.
  bool _confirmingStop = false;
  // True when our own stop-press paused the walk, so Cancel knows to resume it.
  // A walk that was already paused before stop stays paused on Cancel.
  bool _pausedForConfirm = false;
  final GlobalKey _surfaceKey = GlobalKey();

  @override
  void didUpdateWidget(_BottomPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Leaving the active state (walk finished) clears any pending confirmation.
    if (widget.state == RecorderState.idle && _confirmingStop) {
      _confirmingStop = false;
      _pausedForConfirm = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final height = _surfaceKey.currentContext?.size?.height;
      if (height != null) widget.onHeightChanged(height);
    });

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            key: _surfaceKey,
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.88),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(
                  color: cs.onSurface.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
            ),
            padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomInset),
            child: widget.state == RecorderState.idle
                ? (widget.completedWalk != null
                    ? _buildCompleted(l10n)
                    : _buildIdle(l10n))
                : _buildActive(l10n),
          ),
        ),
      ),
    );
  }

  Widget _buildIdle(AppLocalizations l10n) {
    return FilledButton.icon(
      key: const Key('start_button'),
      onPressed: () {
        HapticFeedback.lightImpact();
        widget.onStart();
      },
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 58),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
      icon: const Icon(Icons.play_arrow_rounded, size: 26),
      label: Text(l10n.actionStart.toUpperCase()),
    );
  }

  // Post-walk summary: celebratory check, the walk's final stats, and
  // Done / View route / Share.
  Widget _buildCompleted(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final stats = WalkStats.of(widget.completedWalk!);
    const buttonTextStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.primaryContainer,
          ),
          child: Icon(
            Icons.check_rounded,
            size: 26,
            color: cs.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.walkCompleteTitle,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.walkCompleteSubtitle,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 20),
        IntrinsicHeight(
          child: Row(
            children: [
              _StatBlock(
                label: l10n.statDistance,
                value: stats.formattedDistance(widget.units),
                unit: widget.units == UnitSystem.metric ? 'km' : 'mi',
              ),
              VerticalDivider(color: cs.outlineVariant, width: 1),
              _StatBlock(
                label: l10n.statDuration,
                value:
                    stats.formattedDuration(fallback: l10n.durationUnavailable),
                unit: null,
              ),
              VerticalDivider(color: cs.outlineVariant, width: 1),
              _StatBlock(
                label: l10n.statPace,
                value: stats.formattedPace(widget.units,
                    fallback: l10n.paceUnavailable),
                unit: stats.paceMinPerKm.isFinite
                    ? (widget.units == UnitSystem.metric ? '/km' : '/mi')
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('done_button'),
          onPressed: () {
            HapticFeedback.lightImpact();
            widget.onDismissCompleted();
          },
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
            textStyle: buttonTextStyle,
          ),
          child: Text(l10n.actionDone.toUpperCase()),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('view_route_button'),
                onPressed: widget.onViewRoute,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                  textStyle: buttonTextStyle,
                ),
                child: Text(l10n.actionViewRoute.toUpperCase()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                key: const Key('share_button'),
                onPressed: widget.onShare,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                  textStyle: buttonTextStyle,
                ),
                child: Text(l10n.actionShare.toUpperCase()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActive(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final status = WalkStatusColors.of(context);
    final isRecording = widget.state == RecorderState.recording;
    final stats = widget.snapshot?.stats ??
        WalkStats.fromParts(coordinates: const [], duration: Duration.zero);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Status indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Conventional recorder semantics (green = recording, amber =
                // paused), kept theme-aware via the WalkStatusColors extension.
                color: isRecording ? status.recording : status.paused,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              (_confirmingStop
                      ? l10n.statusConfirmStop
                      : (isRecording
                          ? l10n.statusRecording
                          : l10n.statusPaused))
                  .toUpperCase(),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Stats row
        IntrinsicHeight(
          child: Row(
            children: [
              _StatBlock(
                label: l10n.statDistance,
                value: stats.formattedDistance(widget.units),
                unit: widget.units == UnitSystem.metric ? 'km' : 'mi',
              ),
              VerticalDivider(color: cs.outlineVariant, width: 1),
              _StatBlock(
                label: l10n.statElapsed,
                value:
                    stats.formattedDuration(fallback: l10n.durationUnavailable),
                unit: null,
              ),
              VerticalDivider(color: cs.outlineVariant, width: 1),
              _StatBlock(
                label: l10n.statPace,
                value: stats.formattedPace(widget.units,
                    fallback: l10n.paceUnavailable),
                unit: stats.paceMinPerKm.isFinite
                    ? (widget.units == UnitSystem.metric ? '/km' : '/mi')
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Controls — normal transport row, or the Cancel / Finish confirmation.
        _confirmingStop
            ? _buildConfirmStop(l10n)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.outlined(
                    key: isRecording
                        ? const Key('pause_button')
                        : const Key('resume_button'),
                    onPressed: isRecording ? widget.onPause : widget.onResume,
                    // Tooltip doubles as the TalkBack label for this
                    // icon-only control.
                    tooltip: isRecording ? l10n.actionPause : l10n.actionResume,
                    iconSize: 22,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(52, 52),
                      fixedSize: const Size(52, 52),
                    ),
                    icon: Icon(
                      isRecording
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  const SizedBox(width: 20),
                  IconButton.filled(
                    key: const Key('stop_button'),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      // Freeze the walk (and its counter) while the user
                      // decides whether to finish. Remember that we did so, so
                      // Cancel can resume it.
                      if (widget.state == RecorderState.recording) {
                        widget.onPause();
                        _pausedForConfirm = true;
                      }
                      setState(() => _confirmingStop = true);
                    },
                    tooltip: l10n.actionStop,
                    iconSize: 28,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(64, 64),
                      fixedSize: const Size(64, 64),
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                    ),
                    icon: const Icon(Icons.stop_rounded),
                  ),
                ],
              ),
      ],
    );
  }

  Widget _buildConfirmStop(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    const labelStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: const Key('cancel_stop_button'),
            onPressed: () {
              // Resume only if our stop-press was what paused the walk.
              if (_pausedForConfirm) {
                widget.onResume();
                _pausedForConfirm = false;
              }
              setState(() => _confirmingStop = false);
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
              textStyle: labelStyle,
            ),
            child: Text(l10n.actionCancel.toUpperCase()),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            key: const Key('confirm_stop_button'),
            onPressed: () {
              HapticFeedback.lightImpact();
              widget.onStop();
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
              textStyle: labelStyle,
            ),
            child: Text(l10n.actionFinish.toUpperCase()),
          ),
        ),
      ],
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;

  const _StatBlock({required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 5),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1,
                  ),
                ),
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapChip extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;

  /// Spoken label — both remaining chips are icon-only now that History
  /// moved into the menu, so this is always supplied.
  final String? semanticLabel;

  const _MapChip({
    super.key,
    required this.onPressed,
    required this.icon,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        // M3 uses the elevation surface tint rather than a hard drop shadow.
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        elevation: 4,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 18,
                  ),
                  child: icon,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
