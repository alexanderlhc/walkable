import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/screens/walk_detail_screen.dart';
import 'package:walkable/settings_controller.dart';

final _testWalk = Walk(
  id: 'test-1',
  startTime: DateTime(2024, 1, 1, 10, 0, 0),
  endTime: DateTime(2024, 1, 1, 10, 30, 0),
  duration: const Duration(minutes: 30),
  coordinates: [
    Coordinate(
        lat: 55.6761, lng: 12.5683, recordedAt: DateTime(2024, 1, 1, 10, 0, 0)),
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

// A walk whose every fix shares one coordinate: LatLngBounds.fromPoints gives
// zero-size bounds, which CameraFit.bounds cannot compute a zoom for.
final _singlePointWalk = Walk(
  id: 'test-2',
  startTime: DateTime(2024, 1, 1, 10, 0, 0),
  endTime: DateTime(2024, 1, 1, 10, 5, 0),
  duration: const Duration(minutes: 5),
  coordinates: [
    Coordinate(
        lat: 55.6761, lng: 12.5683, recordedAt: DateTime(2024, 1, 1, 10, 0, 0)),
    Coordinate(
        lat: 55.6761, lng: 12.5683, recordedAt: DateTime(2024, 1, 1, 10, 5, 0)),
  ],
);

// A walk with a known, round distance/duration for exercising unit-system
// formatting: 1609.344 m is exactly one mile (1.61 km), 16 min duration.
final _mileWalk = Walk(
  id: 'test-3',
  startTime: DateTime(2024, 1, 1, 10, 0, 0),
  endTime: DateTime(2024, 1, 1, 10, 16, 0),
  duration: const Duration(minutes: 16),
  distanceMetres: 1609.344,
);

void main() {
  late SettingsController settingsController;
  var prefsValues = <String, Object>{};

  setUp(() {
    prefsValues = {};
  });

  Future<Widget> buildSubject(Walk walk) async {
    SharedPreferences.setMockInitialValues(prefsValues);
    final prefs = await SharedPreferences.getInstance();
    settingsController = SettingsController(SettingsRepository(prefs))..load();
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WalkDetailScreen(
        walk: walk,
        settingsController: settingsController,
      ),
    );
  }

  testWidgets('FlutterMap widget is present', (tester) async {
    await tester.pumpWidget(await buildSubject(_testWalk));
    await tester.pump();
    expect(find.byType(FlutterMap), findsOneWidget);
  });

  testWidgets('stats labels are displayed', (tester) async {
    await tester.pumpWidget(await buildSubject(_testWalk));
    await tester.pump();
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('Pace'), findsOneWidget);
  });

  testWidgets('distance stat shows km unit', (tester) async {
    // Pin the device locale to a metric one: flutter test's default platform
    // locale is en_US (imperial), which would otherwise make this assertion
    // depend on the host environment's locale.
    tester.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(await buildSubject(_testWalk));
    await tester.pump();
    expect(find.textContaining('km'), findsAtLeastNWidgets(1));
  });

  testWidgets('duration stat shows 30:00 for 30-minute walk', (tester) async {
    await tester.pumpWidget(await buildSubject(_testWalk));
    await tester.pump();
    expect(find.text('30:00'), findsOneWidget);
  });

  testWidgets('pace stat shows /km unit', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(await buildSubject(_testWalk));
    await tester.pump();
    expect(find.textContaining('/km'), findsOneWidget);
  });

  testWidgets('renders map for walk with zero-size bounds', (tester) async {
    await tester.pumpWidget(await buildSubject(_singlePointWalk));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(FlutterMap), findsOneWidget);
  });

  testWidgets('shows miles and /mi pace when the imperial override is set',
      (tester) async {
    prefsValues = {'units_override': 'imperial'};

    await tester.pumpWidget(await buildSubject(_mileWalk));
    await tester.pumpAndSettle();

    expect(find.text('1.00 mi'), findsOneWidget);
    expect(find.text('16:00 /mi'), findsOneWidget);
  });
}
