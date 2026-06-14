import 'package:flutter/material.dart';

/// Walkable's brand colour. Every themed colour in the app derives from this
/// single seed, so changing it here re-tints the whole app.
const Color brandSeed = Color(0xFF2F855A);

/// Builds the app theme for a given brightness from the brand seed.
ThemeData buildAppTheme(Brightness brightness) {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: brandSeed,
      brightness: brightness,
    ),
    useMaterial3: true,
  );
}

/// CartoDB raster tiles, label-free so the brand-coloured route stays the
/// focus. Light uses the muted "voyager" style; dark uses "dark matter" so the
/// map matches a dark device theme.
String mapTileUrl(Brightness brightness) => brightness == Brightness.dark
    ? 'https://{s}.basemaps.cartocdn.com/rastertiles/dark_nolabels/{z}/{x}/{y}.png'
    : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}.png';

const List<String> mapTileSubdomains = ['a', 'b', 'c', 'd'];
