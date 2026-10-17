import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where the OpenStreetMap credit links to: the ODbL licence and attribution
/// notice for the map data.
final Uri osmCopyrightUrl =
    Uri.parse('https://www.openstreetmap.org/copyright');

/// Where the CARTO credit links to, as CARTO's basemap terms require.
final Uri cartoAttributionUrl = Uri.parse('https://carto.com/attributions');

/// The tile credit CARTO's basemap terms ask for, verbatim. It is a legal
/// credit rather than UI copy, so it stays the same in every locale.
const String mapCreditText = '© OpenStreetMap contributors, © CARTO';

Future<void> _launchExternally(Uri url) async {
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

/// The full map credit for an interactive map: flutter_map's
/// [SimpleAttributionWidget] reading "© OpenStreetMap contributors, © CARTO",
/// with "OpenStreetMap" and "CARTO" each linking to their own page.
///
/// It is always visible — CARTO's terms don't allow the credit to be hidden
/// behind a tap, which rules out the collapsible [RichAttributionWidget].
/// Place it as a child of a [FlutterMap].
class MapAttribution extends StatefulWidget {
  /// Lifts the credit clear of whatever overlays the bottom of the map (the
  /// walk screen's bottom panel). When set, it already accounts for the
  /// system inset, so the widget's own [SafeArea] bottom inset is dropped.
  final double bottomPadding;

  /// Opens a tapped link; defaults to the external browser. Tests inject a
  /// fake to stay off the url_launcher platform channel.
  final Future<void> Function(Uri url) openUrl;

  const MapAttribution({
    super.key,
    this.bottomPadding = 0,
    this.openUrl = _launchExternally,
  });

  @override
  State<MapAttribution> createState() => _MapAttributionState();
}

class _MapAttributionState extends State<MapAttribution> {
  late final _osmTap = TapGestureRecognizer()
    ..onTap = () => widget.openUrl(osmCopyrightUrl);
  late final _cartoTap = TapGestureRecognizer()
    ..onTap = () => widget.openUrl(cartoAttributionUrl);

  @override
  void dispose() {
    _osmTap.dispose();
    _cartoTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const link = TextStyle(decoration: TextDecoration.underline);
    // SimpleAttributionWidget prefixes "flutter_map | © " itself, so the
    // source starts at "OpenStreetMap".
    return MediaQuery.removePadding(
      context: context,
      removeBottom: widget.bottomPadding > 0,
      child: Padding(
        padding: EdgeInsets.only(bottom: widget.bottomPadding),
        child: DefaultTextStyle.merge(
          style: TextStyle(fontSize: 11, color: cs.onSurface),
          child: SimpleAttributionWidget(
            backgroundColor: cs.surface.withValues(alpha: 0.8),
            source: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'OpenStreetMap',
                    style: link,
                    recognizer: _osmTap,
                  ),
                  const TextSpan(text: ' contributors, © '),
                  TextSpan(text: 'CARTO', style: link, recognizer: _cartoTap),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small, unlinked credit for non-interactive map previews (the history
/// thumbnails), where links can't be tapped: every tap opens the walk, whose
/// detail map carries the full linked [MapAttribution]. Place it as a child of
/// a [FlutterMap].
class CompactMapAttribution extends StatelessWidget {
  const CompactMapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.7),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(4)),
        ),
        child: Text(
          mapCreditText,
          style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
