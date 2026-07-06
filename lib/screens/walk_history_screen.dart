import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/theme.dart';
import 'package:walkable/units.dart';
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

  void _retry() {
    setState(() {
      _walksFuture = widget.repository.findAll();
    });
  }

  /// The list is loaded without coordinates; hydrate the full route before
  /// showing the detail screen.
  Future<void> _openDetail(Walk walk) async {
    final navigator = Navigator.of(context);
    final full = await widget.repository.findById(walk.id) ?? walk;
    if (!mounted) return;
    navigator.pushNamed('/walk-detail', arguments: full);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navHistory)),
      body: FutureBuilder<List<Walk>>(
        future: _walksFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.historyLoadError),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _retry,
                    child: Text(l10n.actionRetry),
                  ),
                ],
              ),
            );
          }
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
                onTap: () => _openDetail(walk),
              );
            },
          );
        },
      ),
    );
  }
}

/// A walk in the history feed: a mini map of the stored route preview (or a
/// placeholder mark for walks persisted before routes were stored), with the
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
    final route = walk.route ?? const [];

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
                SizedBox(
                  height: 168,
                  child: route.isNotEmpty
                      ? _MiniRouteMap(
                          points: [
                            for (final c in route) LatLng(c.lat, c.lng),
                          ],
                        )
                      : Container(
                          color: cs.surfaceContainerHighest,
                          padding: const EdgeInsets.all(18),
                          child: const _RoutePlaceholder(),
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
                    value: l10n.unitKm(stats.formattedDistance(UnitSystem.metric)),
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
                    value: stats.formattedPace(UnitSystem.metric, fallback: l10n.paceUnavailable),
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

/// A non-interactive tile-map preview of a walk's stored route. Wrapped in
/// [IgnorePointer] (with all interaction flags off) so taps fall through to
/// the card's [InkWell].
class _MiniRouteMap extends StatelessWidget {
  final List<LatLng> points;

  const _MiniRouteMap({required this.points});

  // Every point of a route can share one coordinate (a one-point walk, or the
  // user stood still), which makes LatLngBounds.fromPoints zero-size —
  // flutter_map's bounds-zoom fit can't compute a zoom for those. Fall back
  // to centring on the point at a fixed zoom instead (same approach as the
  // detail screen).
  MapOptions _mapOptions() {
    const interaction = InteractionOptions(flags: InteractiveFlag.none);
    final bounds = LatLngBounds.fromPoints(points);
    if (bounds.north == bounds.south && bounds.east == bounds.west) {
      return MapOptions(
        initialCenter: points.first,
        initialZoom: 17,
        interactionOptions: interaction,
      );
    }
    return MapOptions(
      initialCameraFit: CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(24),
      ),
      interactionOptions: interaction,
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FlutterMap(
        options: _mapOptions(),
        children: [
          TileLayer(
            urlTemplate: mapTileUrl(Theme.of(context).brightness),
            subdomains: mapTileSubdomains,
            userAgentPackageName: 'dk.alexanderlhc.walkable',
          ),
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
    );
  }
}

/// The preview mark for walks with no stored route (persisted before the
/// route column existed): the same faint centred dot the route sketch used to
/// draw for empty routes.
class _RoutePlaceholder extends StatelessWidget {
  const _RoutePlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.infinite,
      painter: _PlaceholderDotPainter(color: cs.primary),
    );
  }
}

class _PlaceholderDotPainter extends CustomPainter {
  final Color color;

  _PlaceholderDotPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      size.center(Offset.zero),
      4,
      Paint()..color = color.withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(_PlaceholderDotPainter old) => old.color != color;
}
