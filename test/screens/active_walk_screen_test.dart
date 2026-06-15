import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/screens/active_walk_screen.dart';
import 'package:walkable/walk_recorder.dart';
import 'package:walkable/walk_stats.dart';

class MockWalkRecorder extends Mock implements WalkRecorder {}

class MockLocationService extends Mock implements LocationService {}

class MockWalkRepository extends Mock implements WalkRepository {}

void main() {
  late MockWalkRecorder recorder;
  late MockLocationService locationService;
  late MockWalkRepository repository;
  late StreamController<WalkSnapshot> snapshotsCtrl;

  setUp(() {
    recorder = MockWalkRecorder();
    locationService = MockLocationService();
    repository = MockWalkRepository();
    snapshotsCtrl = StreamController<WalkSnapshot>.broadcast();

    when(() => recorder.state).thenReturn(RecorderState.idle);
    when(() => recorder.snapshots).thenAnswer((_) => snapshotsCtrl.stream);
    when(() => recorder.locationService).thenReturn(locationService);
    when(() => recorder.start(notification: any(named: 'notification')))
        .thenAnswer((_) async => LocationServiceResult.started);
    when(() => recorder.pause()).thenAnswer((_) async {});
    when(() => recorder.resume()).thenAnswer((_) async {});
    when(() => recorder.stop()).thenAnswer((_) async {});
    when(() => recorder.reset()).thenReturn(null);

    when(() => locationService.checkAndRequestPermission())
        .thenAnswer((_) async => true);
    when(() => locationService.watchPosition())
        .thenAnswer((_) => const Stream.empty());
    when(() => locationService.notificationsGranted).thenReturn(true);
    when(() => locationService.batteryOptimizationGranted).thenReturn(true);
  });

  tearDown(() => snapshotsCtrl.close());

  Widget buildSubject({Locale? locale}) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ActiveWalkScreen(recorder: recorder, repository: repository),
      );

  // ─── localization ────────────────────────────────────────────────────────────

  testWidgets('renders Danish strings when the locale is Danish',
      (tester) async {
    await tester.pumpWidget(buildSubject(locale: const Locale('da')));
    await tester.pumpAndSettle();

    expect(find.text('Tidligere gåture'), findsOneWidget);
  });

  // ─── idle state ────────────────────────────────────────────────────────────

  testWidgets('Start button visible in idle state', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('start_button')), findsOneWidget);
    expect(find.byKey(const Key('stop_button')), findsNothing);
  });

  testWidgets('History button visible in idle state', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history_button')), findsOneWidget);
  });

  testWidgets('permission check is requested on startup', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    verify(() => locationService.checkAndRequestPermission()).called(1);
  });

  testWidgets('snackbar shown when location permission is denied',
      (tester) async {
    when(() => locationService.checkAndRequestPermission())
        .thenAnswer((_) async => false);

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('watchPosition stream subscribed after permission granted',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    verify(() => locationService.watchPosition()).called(1);
  });

  testWidgets('watchPosition not subscribed when permission denied',
      (tester) async {
    when(() => locationService.checkAndRequestPermission())
        .thenAnswer((_) async => false);

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    verifyNever(() => locationService.watchPosition());
  });

  // ─── re-centre button ──────────────────────────────────────────────────────

  testWidgets('re-centre button hidden when no position known yet',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recenter_button')), findsNothing);
  });

  testWidgets('re-centre button hidden when permission is denied',
      (tester) async {
    when(() => locationService.checkAndRequestPermission())
        .thenAnswer((_) async => false);

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recenter_button')), findsNothing);
  });

  // ─── recording state ───────────────────────────────────────────────────────

  testWidgets('Stop and Pause buttons visible after tapping Start',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pumpAndSettle();

    verify(() => recorder.start(notification: any(named: 'notification')))
        .called(1);
    expect(find.byKey(const Key('stop_button')), findsOneWidget);
    expect(find.byKey(const Key('pause_button')), findsOneWidget);
    expect(find.byKey(const Key('start_button')), findsNothing);
    expect(find.byKey(const Key('resume_button')), findsNothing);
  });

  testWidgets('warns with a recovery action when notifications are off',
      (tester) async {
    when(() => locationService.notificationsGranted).thenReturn(false);

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(SnackBarAction), findsOneWidget);
  });

  testWidgets('no warning when notifications are granted', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('RECORDING label visible when recording', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pumpAndSettle();

    expect(find.text('RECORDING'), findsOneWidget);
  });

  testWidgets('history button remains visible during recording',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history_button')), findsOneWidget);
  });

  // ─── paused state ──────────────────────────────────────────────────────────

  testWidgets('Resume and Stop buttons visible while paused', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pumpAndSettle();

    when(() => recorder.state).thenReturn(RecorderState.paused);
    await tester.tap(find.byKey(const Key('pause_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('resume_button')), findsOneWidget);
    expect(find.byKey(const Key('stop_button')), findsOneWidget);
    expect(find.byKey(const Key('pause_button')), findsNothing);
    expect(find.byKey(const Key('start_button')), findsNothing);
  });

  testWidgets('PAUSED label visible when paused', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pumpAndSettle();

    when(() => recorder.state).thenReturn(RecorderState.paused);
    await tester.tap(find.byKey(const Key('pause_button')));
    await tester.pumpAndSettle();

    expect(find.text('PAUSED'), findsOneWidget);
  });

  // ─── stats ─────────────────────────────────────────────────────────────────

  testWidgets('stats section shown when recorder emits a snapshot',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    when(() => recorder.state).thenReturn(RecorderState.recording);

    snapshotsCtrl.add(WalkSnapshot(
      stats: const WalkStats(
        distanceMetres: 1500,
        duration: Duration(minutes: 15),
      ),
      polyline: const [
        (lat: 55.676, lng: 12.568),
        (lat: 55.677, lng: 12.569),
      ],
    ));
    await tester.pumpAndSettle();

    // Stat labels confirm the stats section is rendered
    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.text('ELAPSED'), findsOneWidget);
    expect(find.text('PACE'), findsOneWidget);

    // Stat values are in RichText spans
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == '1.50 km',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == '15:00',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('/km'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('stats hidden in idle state', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('RECORDING'), findsNothing);
    expect(find.text('PAUSED'), findsNothing);
  });

  // ─── stop ──────────────────────────────────────────────────────────────────

  testWidgets('tapping Stop calls stop and reset, returns to idle',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pumpAndSettle();

    // Stop is a two-step confirmation: tap Stop, then Finish.
    await tester.tap(find.byKey(const Key('stop_button')));
    await tester.pumpAndSettle();

    when(() => recorder.state).thenReturn(RecorderState.idle);
    await tester.tap(find.byKey(const Key('confirm_stop_button')));
    await tester.pumpAndSettle();

    verify(() => recorder.stop()).called(1);
    verify(() => recorder.reset()).called(1);
    expect(find.byKey(const Key('start_button')), findsOneWidget);
    expect(find.byKey(const Key('stop_button')), findsNothing);
  });
}
