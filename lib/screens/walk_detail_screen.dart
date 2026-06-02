import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/walk_calculator.dart';

class WalkDetailScreen extends StatelessWidget {
  final Walk walk;

  const WalkDetailScreen({super.key, required this.walk});

  @override
  Widget build(BuildContext context) {
    final coords = walk.coordinates.map((c) => LatLng(c.lat, c.lng)).toList();

    final calcCoords =
        walk.coordinates.map((c) => (lat: c.lat, lng: c.lng)).toList();
    final distanceMetres = totalDistance(calcCoords);

    final duration = walk.endTime != null
        ? walk.endTime!.difference(walk.startTime)
        : Duration.zero;

    final paceValue = pace(distanceMetres, duration);

    return Scaffold(
      appBar: AppBar(title: const Text('Walk Detail')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: coords.isNotEmpty
                  ? MapOptions(
                      initialCameraFit: CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(coords),
                        padding: const EdgeInsets.all(32),
                      ),
                    )
                  : const MapOptions(
                      initialCenter: LatLng(55.6761, 12.5683),
                      initialZoom: 14,
                    ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'dk.alexanderlhc.walkable',
                ),
                if (coords.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: coords,
                        strokeWidth: 4,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          _StatsPanel(
            distanceMetres: distanceMetres,
            duration: duration,
            paceMinPerKm: paceValue,
          ),
        ],
      ),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  final double distanceMetres;
  final Duration duration;
  final double paceMinPerKm;

  const _StatsPanel({
    required this.distanceMetres,
    required this.duration,
    required this.paceMinPerKm,
  });

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _formatPace(double p) {
    if (p == double.infinity || p == 0.0) return '--:--';
    final totalSeconds = (p * 60).round();
    final m = totalSeconds ~/ 60;
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s /km';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatItem(
            label: 'Distance',
            value: '${(distanceMetres / 1000).toStringAsFixed(2)} km',
          ),
          _StatItem(
            label: 'Duration',
            value: _formatDuration(duration),
          ),
          _StatItem(
            label: 'Pace',
            value: _formatPace(paceMinPerKm),
          ),
        ],
      ),
    );
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
