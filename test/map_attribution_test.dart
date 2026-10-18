import 'package:flutter/foundation.dart';
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

  group('map data licenses', () {
    setUp(LicenseRegistry.reset);
    tearDown(LicenseRegistry.reset);

    testWidgets('are listed on the license page', (tester) async {
      registerMapDataLicenses();
      await tester.pumpWidget(const MaterialApp(home: LicensePage()));
      await tester.pumpAndSettle();

      expect(find.text('OpenStreetMap'), findsOneWidget);
      expect(find.text('CARTO'), findsOneWidget);
    });

    test('credit OSM contributors under the ODbL and CARTO basemaps', () async {
      registerMapDataLicenses();
      final licenses = await LicenseRegistry.licenses.toList();
      String textOf(String package) => licenses
          .singleWhere((l) => l.packages.contains(package))
          .paragraphs
          .map((p) => p.text)
          .join('\n');

      expect(textOf('OpenStreetMap'),
          allOf(contains('OpenStreetMap contributors'), contains('ODbL')));
      expect(textOf('CARTO'), contains('CARTO basemaps'));
    });
  });
}
