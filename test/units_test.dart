import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:walkable/units.dart';

void main() {
  group('unitSystemForLocale', () {
    test('imperial countries -> imperial', () {
      expect(unitSystemForLocale(const Locale('en', 'US')),
          UnitSystem.imperial);
      expect(unitSystemForLocale(const Locale('en', 'GB')),
          UnitSystem.imperial);
      expect(unitSystemForLocale(const Locale('en', 'LR')),
          UnitSystem.imperial);
      expect(unitSystemForLocale(const Locale('my', 'MM')),
          UnitSystem.imperial);
    });

    test('metric countries -> metric', () {
      expect(unitSystemForLocale(const Locale('da', 'DK')), UnitSystem.metric);
      expect(unitSystemForLocale(const Locale('de', 'DE')), UnitSystem.metric);
      expect(unitSystemForLocale(const Locale('en', 'IE')), UnitSystem.metric);
    });

    test('no country code -> metric', () {
      expect(unitSystemForLocale(const Locale('en')), UnitSystem.metric);
    });
  });
}
