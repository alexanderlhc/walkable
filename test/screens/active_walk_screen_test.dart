import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
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

  testWidgets(
      'stops the live-preview location stream when recording starts',
      (tester) async {
    // geolocator caches its single position stream and ignores the
    // locationSettings of any later getPositionStream() call while one is
    // already active. The live-preview stream (plain settings, no foreground
    // config) is started on screen open; if it stays subscribed when recording
    // begins, recorder.start()'s foreground stream is silently shadowed — no
    // notification and throttled GPS once the screen locks. So the preview must
    // be torn down before recording starts.
    final preview = StreamController<Position>.broadcast();
    addTearDown(preview.close);
    when(() => locationService.watchPosition())
        .thenAnswer((_) => preview.stream);

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();
    expect(preview.hasListener, isTrue,
        reason: 'preview stream should be live before recording');

    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pumpAndSettle();

    expect(preview.hasListener, isFalse,
        reason: 'preview stream must be cancelled when recording starts');
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

  testWidgets('restarts the live preview after stopping', (tester) async {
    // Recording cancels the preview stream; once the walk ends and we return to
    // idle, the preview must be re-subscribed so the blue dot keeps following.
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('stop_button')));
    await tester.pumpAndSettle();
    when(() => recorder.state).thenReturn(RecorderState.idle);
    await tester.tap(find.byKey(const Key('confirm_stop_button')));
    await tester.pumpAndSettle();

    // Once on screen open, once again after the walk ends.
    verify(() => locationService.watchPosition()).called(2);
  });

  // ─── auto-centre on first fix ────────────────────────────────────────────────

  Position pos(double lat, double lng) => Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.utc(2026),
        accuracy: 5.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 1.4,
        speedAccuracy: 0.0,
      );

  // The screen passes its own MapController to FlutterMap, so we can read the
  // resulting camera straight off the rendered widget.
  MapController cameraControllerOf(WidgetTester tester) =>
      tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;

  testWidgets('auto-centres the map on the first fix from watchPosition',
      (tester) async {
    final positions = StreamController<Position>();
    when(() => locationService.watchPosition())
        .thenAnswer((_) => positions.stream);

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    // New York — far from the hardcoded Copenhagen default centre.
    positions.add(pos(40.7128, -74.0060));
    await tester.pumpAndSettle();

    final camera = cameraControllerOf(tester).camera;
    expect(camera.center.latitude, closeTo(40.7128, 0.0001));
    expect(camera.center.longitude, closeTo(-74.0060, 0.0001));

    await positions.close();
  });

  testWidgets('auto-centres the map on the first fix from the snapshots stream',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    when(() => recorder.state).thenReturn(RecorderState.recording);
    snapshotsCtrl.add(WalkSnapshot(
      stats: const WalkStats(distanceMetres: 0, duration: Duration.zero),
      polyline: const [(lat: 40.7128, lng: -74.0060)],
    ));
    await tester.pumpAndSettle();

    final camera = cameraControllerOf(tester).camera;
    expect(camera.center.latitude, closeTo(40.7128, 0.0001));
    expect(camera.center.longitude, closeTo(-74.0060, 0.0001));
  });

  testWidgets('does not re-centre on later fixes (one-shot, lets the user pan)',
      (tester) async {
    final positions = StreamController<Position>();
    when(() => locationService.watchPosition())
        .thenAnswer((_) => positions.stream);

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    positions.add(pos(40.7128, -74.0060)); // first fix → auto-centre
    await tester.pumpAndSettle();

    // Simulate the user panning the map away from the dot.
    final controller = cameraControllerOf(tester);
    controller.move(const LatLng(48.8566, 2.3522), controller.camera.zoom);
    await tester.pumpAndSettle();

    positions.add(pos(34.0522, -118.2437)); // second fix → must NOT hijack camera
    await tester.pumpAndSettle();

    final camera = cameraControllerOf(tester).camera;
    expect(camera.center.latitude, closeTo(48.8566, 0.0001)); // still Paris
    expect(camera.center.longitude, closeTo(2.3522, 0.0001));

    await positions.close();
  });

  testWidgets(
      'recentre chip appears when the dot is hidden behind the bottom panel',
      (tester) async {
    final positions = StreamController<Position>();
    when(() => locationService.watchPosition())
        .thenAnswer((_) => positions.stream);

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    // First fix auto-centres; the dot sits mid-map, comfortably in view.
    positions.add(pos(55.0, 12.0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recenter_button')), findsNothing);

    // A later fix that lands inside the bottom panel's footprint — on the map,
    // and well clear of the screen edges, but hidden behind the panel.
    final panel = tester.getRect(find.byType(BackdropFilter));
    final camera = cameraControllerOf(tester).camera;
    final behindPanel =
        camera.screenOffsetToLatLng(Offset(panel.center.dx, panel.top + 6));
    positions.add(pos(behindPanel.latitude, behindPanel.longitude));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recenter_button')), findsOneWidget);

    await positions.close();
  });
}
