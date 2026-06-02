import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/screens/active_walk_screen.dart';
import 'package:walkable/walk_recorder.dart';

class MockWalkRecorder extends Mock implements WalkRecorder {}

class MockWalkRepository extends Mock implements WalkRepository {}

void main() {
  late MockWalkRecorder recorder;
  late MockWalkRepository repository;
  late StreamController<WalkSnapshot> snapshotsCtrl;

  setUp(() {
    recorder = MockWalkRecorder();
    repository = MockWalkRepository();
    snapshotsCtrl = StreamController<WalkSnapshot>.broadcast();

    when(() => recorder.state).thenReturn(RecorderState.idle);
    when(() => recorder.snapshots).thenAnswer((_) => snapshotsCtrl.stream);
    when(() => recorder.start()).thenAnswer((_) async => LocationServiceResult.started);
    when(() => recorder.stop()).thenAnswer((_) async {});
    when(() => recorder.reset()).thenReturn(null);
  });

  tearDown(() => snapshotsCtrl.close());

  Widget buildSubject() => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ActiveWalkScreen(recorder: recorder, repository: repository),
      );

  testWidgets('Start button is visible in idle state', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.byKey(const Key('start_button')), findsOneWidget);
    expect(find.byKey(const Key('stop_button')), findsNothing);
  });

  testWidgets('Stop button visible after tapping Start', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pumpAndSettle();

    verify(() => recorder.start()).called(1);
    expect(find.byKey(const Key('stop_button')), findsOneWidget);
    expect(find.byKey(const Key('start_button')), findsNothing);
  });

  testWidgets('stats update when recorder emits a snapshot', (tester) async {
    await tester.pumpWidget(buildSubject());

    when(() => recorder.state).thenReturn(RecorderState.recording);

    snapshotsCtrl.add(WalkSnapshot(
      distanceMetres: 1500,
      elapsed: const Duration(minutes: 15),
      paceMinPerKm: 10.0,
      polyline: const [
        (lat: 55.676, lng: 12.568),
        (lat: 55.677, lng: 12.569),
      ],
    ));
    await tester.pump();

    expect(find.text('1.50 km'), findsOneWidget);
    expect(find.text('15:00'), findsOneWidget);
    expect(find.textContaining('/km'), findsOneWidget);
  });
}
