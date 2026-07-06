import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/main.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/settings_controller.dart';
import 'package:walkable/walk_recorder.dart';

class MockWalkRecorder extends Mock implements WalkRecorder {}

class MockLocationService extends Mock implements LocationService {}

class MockWalkRepository extends Mock implements WalkRepository {}

void main() {
  late MockWalkRecorder recorder;
  late MockLocationService locationService;
  late MockWalkRepository repository;
  late StreamController<WalkSnapshot> ctrl;

  setUp(() {
    recorder = MockWalkRecorder();
    locationService = MockLocationService();
    repository = MockWalkRepository();
    ctrl = StreamController<WalkSnapshot>.broadcast();

    when(() => recorder.state).thenReturn(RecorderState.idle);
    when(() => recorder.snapshots).thenAnswer((_) => ctrl.stream);
    when(() => recorder.locationService).thenReturn(locationService);
    when(() => locationService.checkAndRequestPermission())
        .thenAnswer((_) async => true);
    when(() => locationService.watchPosition())
        .thenAnswer((_) => const Stream.empty());
  });

  tearDown(() => ctrl.close());

  testWidgets('WalkableApp shows the main screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settingsController = SettingsController(SettingsRepository(prefs))
      ..load();

    await tester.pumpWidget(
      WalkableApp(
        recorder: recorder,
        repository: repository,
        settingsController: settingsController,
      ),
    );
    await tester.pumpAndSettle();

    // Menu chip is the single top-left entry point
    expect(find.byKey(const Key('menu_button')), findsOneWidget);
    // Start button is present
    expect(find.byKey(const Key('start_button')), findsOneWidget);
  });

  testWidgets('selecting Dansk switches the app language immediately',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settingsController = SettingsController(SettingsRepository(prefs))
      ..load();

    await tester.pumpWidget(
      WalkableApp(
        recorder: recorder,
        repository: repository,
        settingsController: settingsController,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language_da')));
    await tester.pumpAndSettle();

    // The settings screen re-renders in Danish without restart
    expect(find.text('Indstillinger'), findsOneWidget);
    expect(find.text('Sprog'), findsOneWidget);
    // And the choice is persisted
    expect(prefs.getString('locale_override'), 'da');
  });

  testWidgets('starts in Danish when a Danish override was persisted',
      (tester) async {
    SharedPreferences.setMockInitialValues({'locale_override': 'da'});
    final prefs = await SharedPreferences.getInstance();
    final settingsController = SettingsController(SettingsRepository(prefs))
      ..load();

    await tester.pumpWidget(
      WalkableApp(
        recorder: recorder,
        repository: repository,
        settingsController: settingsController,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('menu_button')));
    await tester.pumpAndSettle();

    // History menu item renders in Danish
    expect(find.text('Tidligere gåture'), findsOneWidget);
  });
}
