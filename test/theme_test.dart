import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkable/theme.dart';

void main() {
  group('mapTileUrl', () {
    test('appends the CARTO key to both styles', () {
      expect(
        mapTileUrl(Brightness.light, apiKey: 'abc123'),
        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}.png?key=abc123',
      );
      expect(
        mapTileUrl(Brightness.dark, apiKey: 'abc123'),
        'https://{s}.basemaps.cartocdn.com/rastertiles/dark_nolabels/{z}/{x}/{y}.png?key=abc123',
      );
    });

    test('percent-encodes the key', () {
      expect(mapTileUrl(Brightness.light, apiKey: 'a b&c'),
          endsWith('.png?key=a+b%26c'));
    });

    test('without a key, falls back to the keyless URL', () {
      expect(
        mapTileUrl(Brightness.light, apiKey: ''),
        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}.png',
      );
    });

    test('defaults to the build-time key, which tests build without', () {
      expect(mapTileUrl(Brightness.dark), isNot(contains('key=')));
    });
  });
}
