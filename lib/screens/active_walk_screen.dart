import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/screens/walk_history_screen.dart';
import 'package:walkable/theme.dart';
import 'package:walkable/walk_recorder.dart';
import 'package:walkable/walk_stats.dart';

class ActiveWalkScreen extends StatefulWidget {
  final WalkRecorder recorder;
  final WalkRepository repository;

  const ActiveWalkScreen({
    super.key,
    required this.recorder,
    required this.repository,
  });

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
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    final granted =
        await widget.recorder.locationService.checkAndRequestPermission();
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
    _positionSub =
        widget.recorder.locationService.watchPosition().listen((pos) {
      if (!mounted) return;
      final latlng = LatLng(pos.latitude, pos.longitude);
      setState(() => _currentPosition = latlng);
      _maybeAutoCentre(latlng);
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

  Future<void> _onStart() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await widget.recorder.start(
      notification: ForegroundNotificationText(
        title: l10n.notificationTitle,
        body: l10n.notificationText,
      ),
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
    setState(() => _recorderState = RecorderState.recording);
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
    await widget.recorder.resume();
    if (!mounted) return;
    setState(() => _recorderState = RecorderState.recording);
  }

  Future<void> _onStop() async {
    await widget.recorder.stop();
    widget.recorder.reset();
    if (!mounted) return;
    setState(() => _recorderState = RecorderState.idle);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final points =
        _snapshot?.polyline.map((c) => LatLng(c.lat, c.lng)).toList() ?? [];

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
              if (_currentPosition != null)
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
            ],
          ),
          _BottomPanel(
            state: _recorderState,
            snapshot: _snapshot,
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
          // History pill — top left
          Positioned(
            top: topPadding,
            left: 12,
            child: _MapChip(
              key: const Key('history_button'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      WalkHistoryScreen(repository: widget.repository),
                ),
              ),
              icon: const Icon(Icons.history, size: 18),
              label: Text(l10n.navHistory),
            ),
          ),
          // Re-centre — top right, only when dot is off-screen
          if (_locationPermissionGranted && _positionOutOfView)
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
}

// ─── Bottom control panel ────────────────────────────────────────────────────
// Single frosted-glass surface that owns both stats and controls.
// Nothing outside this widget touches the bottom of the screen.

class _BottomPanel extends StatefulWidget {
  final RecorderState state;
  final WalkSnapshot? snapshot;
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
                ? _buildIdle(l10n)
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
                value: stats.formattedDistance(),
                unit: 'km',
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
                value: stats.formattedPace(fallback: l10n.paceUnavailable),
                unit: stats.paceMinPerKm.isFinite ? '/km' : null,
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
  final Widget? label;

  /// Spoken label for icon-only chips (those with no [label] text). A chip
  /// with a text label already reads it, so this can be left null there.
  final String? semanticLabel;

  const _MapChip({
    super.key,
    required this.onPressed,
    required this.icon,
    this.label,
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
            padding: EdgeInsets.symmetric(
              horizontal: label != null ? 12 : 10,
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
                if (label != null) ...[
                  const SizedBox(width: 6),
                  DefaultTextStyle(
                    style: Theme.of(context).textTheme.labelLarge!.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                    child: label!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
