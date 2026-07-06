import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/screens/walk_history_screen.dart';

class MockWalkRepository extends Mock implements WalkRepository {}

void main() {
  late MockWalkRepository mockRepository;

  setUp(() {
    mockRepository = MockWalkRepository();
  });

  Widget buildSubject() => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routes: {
          '/walk-detail': (_) => const Scaffold(body: Text('Walk Detail')),
        },
        home: WalkHistoryScreen(repository: mockRepository),
      );

  testWidgets('shows empty state when no walks exist', (tester) async {
    when(() => mockRepository.findAll()).thenAnswer((_) async => []);

    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.text('No walks yet'), findsOneWidget);
  });

  testWidgets('renders a row for each saved walk', (tester) async {
    when(() => mockRepository.findAll()).thenAnswer((_) async => [
          Walk(
            id: 'w1',
            startTime: DateTime(2026, 6, 1, 9, 0),
            endTime: DateTime(2026, 6, 1, 9, 30),
            coordinates: [
              Coordinate(
                  lat: 55.676,
                  lng: 12.568,
                  recordedAt: DateTime(2026, 6, 1, 9, 0)),
              Coordinate(
                  lat: 55.677,
                  lng: 12.569,
                  recordedAt: DateTime(2026, 6, 1, 9, 15)),
            ],
          ),
          Walk(
            id: 'w2',
            startTime: DateTime(2026, 5, 15, 8, 0),
            endTime: DateTime(2026, 5, 15, 8, 45),
          ),
        ]);

    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.text('Mon, Jun 1'), findsOneWidget);
    expect(find.text('Fri, May 15'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));
  });

  testWidgets('tapping a row hydrates the walk and navigates to detail',
      (tester) async {
    when(() => mockRepository.findAll()).thenAnswer((_) async => [
          Walk(
            id: 'w1',
            startTime: DateTime(2026, 6, 1, 9, 0),
            endTime: DateTime(2026, 6, 1, 9, 30),
          ),
        ]);
    // The list walk carries no coordinates; the detail route is re-fetched.
    when(() => mockRepository.findById('w1')).thenAnswer((_) async => Walk(
          id: 'w1',
          startTime: DateTime(2026, 6, 1, 9, 0),
          endTime: DateTime(2026, 6, 1, 9, 30),
          coordinates: [
            Coordinate(
                lat: 55.676,
                lng: 12.568,
                recordedAt: DateTime(2026, 6, 1, 9, 0)),
          ],
        ));

    await tester.pumpWidget(buildSubject());
    await tester.pump();

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();

    expect(find.text('Walk Detail'), findsOneWidget);
    verify(() => mockRepository.findById('w1')).called(1);
  });

  testWidgets('renders the stored distance without coordinates',
      (tester) async {
    when(() => mockRepository.findAll()).thenAnswer((_) async => [
          Walk(
            id: 'w1',
            startTime: DateTime(2026, 6, 1, 9, 0),
            endTime: DateTime(2026, 6, 1, 9, 30),
            duration: const Duration(minutes: 25),
            distanceMetres: 1234.5,
          ),
        ]);

    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.text('1.23 km'), findsOneWidget);
  });

  testWidgets('renders a mini map with the stored route polyline',
      (tester) async {
    when(() => mockRepository.findAll()).thenAnswer((_) async => [
          Walk(
            id: 'w1',
            startTime: DateTime(2026, 6, 1, 9, 0),
            endTime: DateTime(2026, 6, 1, 9, 30),
            duration: const Duration(minutes: 25),
            distanceMetres: 127.5,
            route: const [
              (lat: 55.676, lng: 12.568),
              (lat: 55.677, lng: 12.569),
            ],
          ),
        ]);

    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.byType(FlutterMap), findsOneWidget);
    final layer = tester.widget<PolylineLayer>(
        find.byWidgetPredicate((w) => w is PolylineLayer));
    expect(layer.polylines.single.points, const [
      LatLng(55.676, 12.568),
      LatLng(55.677, 12.569),
    ]);
    // Taps must fall through the map to the card's InkWell.
    expect(
      find.ancestor(
          of: find.byType(FlutterMap), matching: find.byType(IgnorePointer)),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('renders a map for a route where every point is identical',
      (tester) async {
    // Zero-size bounds can't drive a bounds fit; the card falls back to a
    // fixed zoom instead of throwing.
    when(() => mockRepository.findAll()).thenAnswer((_) async => [
          Walk(
            id: 'w1',
            startTime: DateTime(2026, 6, 1, 9, 0),
            endTime: DateTime(2026, 6, 1, 9, 30),
            route: const [
              (lat: 55.676, lng: 12.568),
              (lat: 55.676, lng: 12.568),
            ],
          ),
        ]);

    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(FlutterMap), findsOneWidget);
  });

  testWidgets('keeps the placeholder for walks without a stored route',
      (tester) async {
    when(() => mockRepository.findAll()).thenAnswer((_) async => [
          Walk(
            id: 'w1',
            startTime: DateTime(2026, 6, 1, 9, 0),
            endTime: DateTime(2026, 6, 1, 9, 30),
          ),
        ]);

    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.byType(FlutterMap), findsNothing);
    expect(find.byType(Card), findsOneWidget);
  });

  testWidgets('shows an error state with retry when loading fails',
      (tester) async {
    when(() => mockRepository.findAll())
        .thenAnswer((_) async => throw Exception('db is corrupt'));

    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.text("Couldn't load your walks"), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Retry re-runs findAll; let it succeed this time.
    when(() => mockRepository.findAll()).thenAnswer((_) async => []);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();

    expect(find.text('No walks yet'), findsOneWidget);
  });
}
