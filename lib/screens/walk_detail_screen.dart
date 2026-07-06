import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/theme.dart';
import 'package:walkable/walk_stats.dart';

class WalkDetailScreen extends StatelessWidget {
  final Walk walk;

  const WalkDetailScreen({super.key, required this.walk});

  // Every fix of a walk can share one coordinate (a one-point walk, or the
  // user stood still), which makes LatLngBounds.fromPoints zero-size —
  // flutter_map's bounds-zoom fit can't compute a zoom for those. Fall back to
  // centring on the point at a fixed zoom instead.
  MapOptions _mapOptions(List<LatLng> coords) {
    if (coords.isEmpty) {
      return const MapOptions(
        initialCenter: LatLng(55.6761, 12.5683),
        initialZoom: 14,
      );
    }
    final bounds = LatLngBounds.fromPoints(coords);
    if (bounds.north == bounds.south && bounds.east == bounds.west) {
      return MapOptions(initialCenter: coords.first, initialZoom: 17);
    }
    return MapOptions(
      initialCameraFit: CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(32),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coords = walk.coordinates.map((c) => LatLng(c.lat, c.lng)).toList();
    final stats = WalkStats.of(walk);

    return Scaffold(
      appBar:
          AppBar(title: Text(AppLocalizations.of(context)!.screenWalkDetail)),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: _mapOptions(coords),
              children: [
                TileLayer(
                  urlTemplate: mapTileUrl(Theme.of(context).brightness),
                  subdomains: mapTileSubdomains,
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
          _StatsPanel(stats: stats),
        ],
      ),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  final WalkStats stats;

  const _StatsPanel({required this.stats});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pace = stats.formattedPace(fallback: l10n.paceUnavailable);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatItem(
            label: l10n.statDistance,
            value: l10n.unitKm(stats.formattedDistance()),
          ),
          _StatItem(
            label: l10n.statDuration,
            value: stats.formattedDuration(fallback: l10n.durationUnavailable),
          ),
          _StatItem(
            label: l10n.statPace,
            value: stats.paceMinPerKm.isFinite ? '$pace /km' : pace,
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
