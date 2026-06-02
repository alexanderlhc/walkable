import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/screens/walk_history_screen.dart';
import 'package:walkable/walk_recorder.dart';

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

  @override
  void initState() {
    super.initState();
    _recorderState = widget.recorder.state;
    _sub = widget.recorder.snapshots.listen((snapshot) {
      setState(() {
        _snapshot = snapshot;
        _recorderState = widget.recorder.state;
      });
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _onStart() async {
    final result = await widget.recorder.start();
    if (!mounted) return;
    if (result == LocationServiceResult.permissionDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.locationPermissionDenied),
        ),
      );
      return;
    }
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
    final points = _snapshot?.polyline
            .map((c) => LatLng(c.lat, c.lng))
            .toList() ??
        [];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: l10n.navHistory,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    WalkHistoryScreen(repository: widget.repository),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(55.6761, 12.5683),
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
            ],
          ),
          _StatsOverlay(snapshot: _snapshot),
        ],
      ),
      floatingActionButton: _recorderState == RecorderState.idle
          ? FloatingActionButton.extended(
              key: const Key('start_button'),
              onPressed: _onStart,
              label: Text(l10n.actionStart),
              icon: const Icon(Icons.play_arrow),
            )
          : FloatingActionButton.extended(
              key: const Key('stop_button'),
              onPressed: _onStop,
              label: Text(l10n.actionStop),
              icon: const Icon(Icons.stop),
              backgroundColor: Colors.red,
            ),
    );
  }
}

class _StatsOverlay extends StatelessWidget {
  final WalkSnapshot? snapshot;

  const _StatsOverlay({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dist = snapshot?.distanceMetres ?? 0.0;
    final elapsed = snapshot?.elapsed ?? Duration.zero;
    final paceVal = snapshot?.paceMinPerKm ?? double.infinity;

    return Positioned(
      bottom: 88,
      left: 16,
      right: 16,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatItem(
                label: l10n.statDistance,
                value: l10n.unitKm((dist / 1000).toStringAsFixed(2)),
              ),
              _StatItem(
                label: l10n.statElapsed,
                value: _formatDuration(elapsed),
              ),
              _StatItem(
                label: l10n.statPace,
                value: _formatPace(paceVal, fallback: l10n.paceUnavailable),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  static String _formatPace(double p, {required String fallback}) {
    if (p == double.infinity || p == 0.0) return fallback;
    final totalSeconds = (p * 60).round();
    final m = totalSeconds ~/ 60;
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s /km';
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
