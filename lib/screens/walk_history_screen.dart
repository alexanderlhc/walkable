import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/walk_stats.dart';

class WalkHistoryScreen extends StatefulWidget {
  final WalkRepository repository;

  const WalkHistoryScreen({super.key, required this.repository});

  @override
  State<WalkHistoryScreen> createState() => _WalkHistoryScreenState();
}

class _WalkHistoryScreenState extends State<WalkHistoryScreen> {
  late Future<List<Walk>> _walksFuture;

  @override
  void initState() {
    super.initState();
    _walksFuture = widget.repository.findAll();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navHistory)),
      body: FutureBuilder<List<Walk>>(
        future: _walksFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final walks = snapshot.data!;
          if (walks.isEmpty) {
            return Center(child: Text(l10n.historyEmpty));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: walks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final walk = walks[index];
              return _WalkCard(
                walk: walk,
                onTap: () => Navigator.of(context)
                    .pushNamed('/walk-detail', arguments: walk),
              );
            },
          );
        },
      ),
    );
  }
}

/// A walk in the history feed: the recorded route rendered large, with the
/// date and the headline stats (distance, duration, pace) beneath it.
class _WalkCard extends StatelessWidget {
  final Walk walk;
  final VoidCallback onTap;

  const _WalkCard({required this.walk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final stats = WalkStats.of(walk);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                Container(
                  height: 168,
                  color: cs.surfaceContainerHighest,
                  padding: const EdgeInsets.all(18),
                  child: _RouteSketch(
                    coordinates: walk.coordinates,
                    color: cs.primary,
                    strokeWidth: 4,
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: _DatePill(
                    text: DateFormat.MMMEd(locale).format(walk.startTime),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 18),
              child: Row(
                children: [
                  _Stat(
                    value: l10n.unitKm(stats.formattedDistance()),
                    label: l10n.statDistance,
                    emphasized: true,
                  ),
                  const SizedBox(width: 28),
                  _Stat(
                    value: stats.formattedDuration(
                        fallback: l10n.durationUnavailable),
                    label: l10n.statDuration,
                  ),
                  const SizedBox(width: 28),
                  _Stat(
                    value: stats.formattedPace(fallback: l10n.paceUnavailable),
                    label: l10n.statPace,
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final bool emphasized;

  const _Stat({
    required this.value,
    required this.label,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: (emphasized ? t.titleLarge : t.titleMedium)
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(label, style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _DatePill extends StatelessWidget {
  final String text;
  const _DatePill({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Draws a recorded route as a normalized vector path — no map tiles, so it
/// renders instantly and offline.
class _RouteSketch extends StatelessWidget {
  final List<Coordinate> coordinates;
  final Color color;
  final double strokeWidth;

  const _RouteSketch({
    required this.coordinates,
    required this.color,
    this.strokeWidth = 4,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _RoutePainter(
        coordinates: coordinates,
        color: color,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<Coordinate> coordinates;
  final Color color;
  final double strokeWidth;

  _RoutePainter({
    required this.coordinates,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (coordinates.length < 2) {
      canvas.drawCircle(
        size.center(Offset.zero),
        strokeWidth,
        Paint()..color = color.withValues(alpha: 0.4),
      );
      return;
    }

    var minLat = coordinates.first.lat, maxLat = coordinates.first.lat;
    var minLng = coordinates.first.lng, maxLng = coordinates.first.lng;
    for (final c in coordinates) {
      minLat = math.min(minLat, c.lat);
      maxLat = math.max(maxLat, c.lat);
      minLng = math.min(minLng, c.lng);
      maxLng = math.max(maxLng, c.lng);
    }

    final pad = strokeWidth * 2 + 6;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    final spanLng = (maxLng - minLng).abs();
    final spanLat = (maxLat - minLat).abs();
    final scale = math.min(
      w / (spanLng == 0 ? 1e-9 : spanLng),
      h / (spanLat == 0 ? 1e-9 : spanLat),
    );
    final ox = pad + (w - spanLng * scale) / 2;
    final oy = pad + (h - spanLat * scale) / 2;

    Offset project(Coordinate c) => Offset(
          ox + (c.lng - minLng) * scale,
          oy + (maxLat - c.lat) * scale, // north is up
        );

    final first = project(coordinates.first);
    final path = Path()..moveTo(first.dx, first.dy);
    for (final c in coordinates.skip(1)) {
      final p = project(c);
      path.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Start (faint) and end (solid) markers.
    canvas.drawCircle(project(coordinates.first), strokeWidth * 1.4,
        Paint()..color = color.withValues(alpha: 0.35));
    canvas.drawCircle(
        project(coordinates.last), strokeWidth * 1.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.coordinates != coordinates ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
