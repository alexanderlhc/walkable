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
    extensions: [
      brightness == Brightness.dark
          ? WalkStatusColors.dark
          : WalkStatusColors.light,
    ],
  );
}

/// Semantic colours for the walk's transport state. These follow the
/// universal recorder convention (green = recording, amber = paused) rather
/// than the brand seed: the convention is orthogonal to branding, so it must
/// stay legible no matter what [brandSeed] is changed to. (Stop/finish keep
/// using [ColorScheme.error], which is already conventionally red.)
///
/// Each value has a light/dark variant so the dot stays readable against both
/// surfaces — brighter on dark, deeper on light.
@immutable
class WalkStatusColors extends ThemeExtension<WalkStatusColors> {
  /// "Go" / actively recording.
  final Color recording;

  /// Held / paused.
  final Color paused;

  const WalkStatusColors({required this.recording, required this.paused});

  static const light = WalkStatusColors(
    recording: Color(0xFF1E8E3E),
    paused: Color(0xFFF29900),
  );

  static const dark = WalkStatusColors(
    recording: Color(0xFF81C995),
    paused: Color(0xFFFDD663),
  );

  /// Resolves the status colours from [context], falling back to the
  /// brightness-appropriate defaults if the extension isn't installed (e.g. a
  /// bare [MaterialApp] in a widget test).
  static WalkStatusColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<WalkStatusColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  WalkStatusColors copyWith({Color? recording, Color? paused}) =>
      WalkStatusColors(
        recording: recording ?? this.recording,
        paused: paused ?? this.paused,
      );

  @override
  WalkStatusColors lerp(WalkStatusColors? other, double t) {
    if (other == null) return this;
    return WalkStatusColors(
      recording: Color.lerp(recording, other.recording, t)!,
      paused: Color.lerp(paused, other.paused, t)!,
    );
  }
}

/// CartoDB raster tiles, label-free so the brand-coloured route stays the
/// focus. Light uses the muted "voyager" style; dark uses "dark matter" so the
/// map matches a dark device theme.
String mapTileUrl(Brightness brightness) => brightness == Brightness.dark
    ? 'https://{s}.basemaps.cartocdn.com/rastertiles/dark_nolabels/{z}/{x}/{y}.png'
    : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}.png';

const List<String> mapTileSubdomains = ['a', 'b', 'c', 'd'];
