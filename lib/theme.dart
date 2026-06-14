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
