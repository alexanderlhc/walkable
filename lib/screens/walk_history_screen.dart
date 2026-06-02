import 'package:flutter/material.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/walk_calculator.dart';

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
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.navHistory)),
      body: FutureBuilder<List<Walk>>(
        future: _walksFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final walks = snapshot.data!;
          if (walks.isEmpty) {
            return Center(
                child: Text(AppLocalizations.of(context)!.historyEmpty));
          }
          return ListView.builder(
            itemCount: walks.length,
            itemBuilder: (context, index) {
              final walk = walks[index];
              return _WalkRow(
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

class _WalkRow extends StatelessWidget {
  final Walk walk;
  final VoidCallback onTap;

  const _WalkRow({required this.walk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      title: Text(_formatDate(walk.startTime)),
      subtitle: Text(
          '${l10n.unitKm(_distanceKm(walk))} · ${_duration(walk, fallback: l10n.durationUnavailable)}'),
      onTap: onTap,
    );
  }

  static String _formatDate(DateTime d) {
    final y = d.year;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String _distanceKm(Walk walk) {
    final coords =
        walk.coordinates.map((c) => (lat: c.lat, lng: c.lng)).toList();
    final metres = totalDistance(coords);
    return (metres / 1000).toStringAsFixed(2);
  }

  static String _duration(Walk walk, {required String fallback}) {
    if (walk.endTime == null) return fallback;
    final diff = walk.endTime!.difference(walk.startTime);
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
