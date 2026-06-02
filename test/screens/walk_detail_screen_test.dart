import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/screens/walk_detail_screen.dart';

final _testWalk = Walk(
  id: 'test-1',
  startTime: DateTime(2024, 1, 1, 10, 0, 0),
  endTime: DateTime(2024, 1, 1, 10, 30, 0),
  coordinates: [
    Coordinate(
        lat: 55.6761,
        lng: 12.5683,
        recordedAt: DateTime(2024, 1, 1, 10, 0, 0)),
    Coordinate(
        lat: 55.6800,
        lng: 12.5700,
        recordedAt: DateTime(2024, 1, 1, 10, 15, 0)),
    Coordinate(
        lat: 55.6850,
        lng: 12.5750,
        recordedAt: DateTime(2024, 1, 1, 10, 30, 0)),
  ],
);

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('FlutterMap widget is present', (tester) async {
    await tester.pumpWidget(_wrap(WalkDetailScreen(walk: _testWalk)));
    await tester.pump();
    expect(find.byType(FlutterMap), findsOneWidget);
  });

  testWidgets('stats labels are displayed', (tester) async {
    await tester.pumpWidget(_wrap(WalkDetailScreen(walk: _testWalk)));
    await tester.pump();
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('Pace'), findsOneWidget);
  });

  testWidgets('distance stat shows km unit', (tester) async {
    await tester.pumpWidget(_wrap(WalkDetailScreen(walk: _testWalk)));
    await tester.pump();
    expect(find.textContaining('km'), findsAtLeastNWidgets(1));
  });

  testWidgets('duration stat shows 30:00 for 30-minute walk', (tester) async {
    await tester.pumpWidget(_wrap(WalkDetailScreen(walk: _testWalk)));
    await tester.pump();
    expect(find.text('30:00'), findsOneWidget);
  });

  testWidgets('pace stat shows /km unit', (tester) async {
    await tester.pumpWidget(_wrap(WalkDetailScreen(walk: _testWalk)));
    await tester.pump();
    expect(find.textContaining('/km'), findsOneWidget);
  });
}
