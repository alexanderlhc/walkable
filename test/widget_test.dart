import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:walkable/main.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/walk_recorder.dart';

class MockWalkRecorder extends Mock implements WalkRecorder {}

class MockWalkRepository extends Mock implements WalkRepository {}

void main() {
  testWidgets('WalkableApp renders title', (WidgetTester tester) async {
    final recorder = MockWalkRecorder();
    final repository = MockWalkRepository();
    final ctrl = StreamController<WalkSnapshot>.broadcast();

    when(() => recorder.state).thenReturn(RecorderState.idle);
    when(() => recorder.snapshots).thenAnswer((_) => ctrl.stream);

    await tester.pumpWidget(
      WalkableApp(recorder: recorder, repository: repository),
    );

    expect(find.text('Walkable'), findsWidgets);

    await ctrl.close();
  });
}
