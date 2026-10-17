import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// MainActivity's power channel: Battery Saver state, power settings
/// shortcuts and the phone's manufacturer.
const powerChannel = MethodChannel('walkable/power');

/// dontkillmyapp.com pages for the manufacturers whose battery managers it
/// rates as stopping background apps (2 of 5 or worse), keyed by the
/// lowercase `Build.MANUFACTURER`. Stock-Android makers (Google, Nokia/HMD,
/// HTC) score 0 and get no page.
///
/// Only a link, never an OEM settings screen: the autostart and "protected
/// apps" pages are private activities that move between firmware versions
/// and can't be resolved without declaring each OEM package, so the page's
/// per-version steps are the reliable route.
const _dontKillMyAppSlugs = {
  'asus': 'asus',
  'blackview': 'blackview',
  'honor': 'huawei',
  'huawei': 'huawei',
  'lenovo': 'lenovo',
  'meizu': 'meizu',
  'motorola': 'motorola',
  'oneplus': 'oneplus',
  'oppo': 'oppo',
  'realme': 'realme',
  'samsung': 'samsung',
  'sony': 'sony',
  'tecno': 'tecno',
  'ulefone': 'ulefone',
  'unihertz': 'unihertz',
  'vivo': 'vivo',
  'wiko': 'wiko',
  'xiaomi': 'xiaomi',
};

/// The dontkillmyapp.com page explaining how to keep apps running on phones
/// by [manufacturer], or null when its battery manager leaves apps alone.
Uri? dontKillMyAppPage(String manufacturer) {
  final slug = _dontKillMyAppSlugs[manufacturer.trim().toLowerCase()];
  return slug == null ? null : Uri.https('dontkillmyapp.com', '/$slug');
}

/// Shortcuts to the system's power settings, through MainActivity's
/// `walkable/power` channel. Best-effort: off Android, or on any failure,
/// nothing opens.
class PowerSettings {
  const PowerSettings();

  /// Opens Android's Battery Saver settings. Returns whether a settings
  /// screen opened.
  Future<bool> openBatterySaverSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await powerChannel
              .invokeMethod<bool>('openBatterySaverSettings') ??
          false;
    } catch (e) {
      debugPrint('PowerSettings: opening Battery Saver settings failed: $e');
      return false;
    }
  }

  /// The dontkillmyapp.com page for this phone's manufacturer; see
  /// [dontKillMyAppPage].
  Future<Uri?> manufacturerHelpPage() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final manufacturer =
          await powerChannel.invokeMethod<String>('manufacturer');
      return manufacturer == null ? null : dontKillMyAppPage(manufacturer);
    } catch (e) {
      debugPrint('PowerSettings: reading the manufacturer failed: $e');
      return null;
    }
  }

  /// Opens [page] in the browser.
  Future<void> openPage(Uri page) async {
    await launchUrl(page, mode: LaunchMode.externalApplication);
  }
}
