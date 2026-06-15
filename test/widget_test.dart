import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/main.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/walk_recorder.dart';

class MockWalkRecorder extends Mock implements WalkRecorder {}

class MockLocationService extends Mock implements LocationService {}

class MockWalkRepository extends Mock implements WalkRepository {}

void main() {
  testWidgets('WalkableApp shows the main screen', (WidgetTester tester) async {
    final recorder = MockWalkRecorder();
    final locationService = MockLocationService();
    final repository = MockWalkRepository();
    final ctrl = StreamController<WalkSnapshot>.broadcast();

    when(() => recorder.state).thenReturn(RecorderState.idle);
    when(() => recorder.snapshots).thenAnswer((_) => ctrl.stream);
    when(() => recorder.locationService).thenReturn(locationService);
    when(() => locationService.checkAndRequestPermission())
        .thenAnswer((_) async => true);
    when(() => locationService.watchPosition())
        .thenAnswer((_) => const Stream.empty());

    await tester.pumpWidget(
      WalkableApp(recorder: recorder, repository: repository),
    );
    await tester.pumpAndSettle();

    // App title appears via localisation in the history chip
    expect(
      find.byWidgetPredicate((w) =>
          w is Text &&
          (w.data?.contains(
                  RegExp(r'History|Historik', caseSensitive: false)) ??
              false)),
      findsOneWidget,
    );
    // Start button is present
    expect(find.byKey(const Key('start_button')), findsOneWidget);

    await ctrl.close();
  });
}
