import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

    expect(find.text('2026-06-01'), findsOneWidget);
    expect(find.text('2026-05-15'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('tapping a row navigates to walk detail', (tester) async {
    when(() => mockRepository.findAll()).thenAnswer((_) async => [
          Walk(
            id: 'w1',
            startTime: DateTime(2026, 6, 1, 9, 0),
            endTime: DateTime(2026, 6, 1, 9, 30),
          ),
        ]);

    await tester.pumpWidget(buildSubject());
    await tester.pump();

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('Walk Detail'), findsOneWidget);
  });
}
