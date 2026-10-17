import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkable/map_attribution.dart';

void main() {
  Future<List<Uri>> pumpAndTap(WidgetTester tester, String linkText) async {
    final opened = <Uri>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MapAttribution(openUrl: (url) async => opened.add(url)),
      ),
    ));
    await tester.tapOnText(find.textRange.ofSubstring(linkText));
    return opened;
  }

  testWidgets('credits OpenStreetMap contributors and CARTO', (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: MapAttribution())));

    expect(
      find.textContaining('OpenStreetMap contributors, © CARTO',
          findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('OpenStreetMap links to the OSM copyright page', (tester) async {
    expect(await pumpAndTap(tester, 'OpenStreetMap'), [osmCopyrightUrl]);
    expect(
        osmCopyrightUrl.toString(), 'https://www.openstreetmap.org/copyright');
  });

  testWidgets('CARTO links to the CARTO attributions page', (tester) async {
    expect(await pumpAndTap(tester, 'CARTO'), [cartoAttributionUrl]);
    expect(cartoAttributionUrl.toString(), 'https://carto.com/attributions');
  });

  testWidgets('compact credit shows the full credit text', (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CompactMapAttribution())));

    expect(find.text('© OpenStreetMap contributors, © CARTO'), findsOneWidget);
  });
}
