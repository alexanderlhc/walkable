# Battery Saver and manufacturer battery managers

What Walkable does to keep a walk recording on battery-restricted phones, and
what it deliberately leaves out (issue #45).

## Battery Saver (stock Android)

- **At start and on resume** the app reads `PowerManager.getLocationPowerSaveMode()`.
  Modes 1, 2 and 4 cut or throttle location with the screen off; the app warns.
- **Mid-walk** MainActivity listens for `PowerManager.ACTION_POWER_SAVE_MODE_CHANGED`
  while a walk records (EventChannel `walkable/power/locationPowerSaveMode`).
  This fires both when the walker turns Battery Saver on and when it switches
  on by itself at low battery. When location becomes restricted, the walk
  screen shows the warning and posts a "Battery Saver warnings" notification
  for a phone in a pocket. When the restriction lifts, or the walk pauses or
  ends, the notification is withdrawn.
- **Shortcut.** The warning, and Settings → Background tracking, open
  `Settings.ACTION_BATTERY_SAVER_SETTINGS`, or `ACTION_POWER_USAGE_SUMMARY`
  where a phone lacks that page. Each is resolved before launching.
- Nothing can override Battery Saver's location mode, so the app can only
  warn.

## Manufacturer battery managers

Samsung, Xiaomi, Huawei/Honor, OnePlus, Oppo, Vivo and others can stop apps
or their foreground services even with the battery-optimisation exemption
granted.

**Implemented.** On phones from makers that dontkillmyapp.com rates 2 of 5 or
worse, Settings → Background tracking offers "Keep walks recording". It opens
that maker's dontkillmyapp.com page, which has per-firmware steps. The maker
comes from `Build.MANUFACTURER`. The mapping in `lib/power_settings.dart`
follows the site's `/api/v2/<vendor>.json` `manufacturer` fields. Stock-Android
makers (Google, Nokia/HMD, HTC) score 0 and get no link.

**Not implemented, because it isn't reliable:**

- **Deep links into OEM autostart / protected-apps screens**, such as
  `com.miui.securitycenter/...AutoStartManagementActivity` or Huawei's startup
  manager. These are private activities, not APIs. They are renamed or removed
  between firmware versions, and some throw `SecurityException` when launched.
  On Android 11+ they also can't be resolved without declaring every OEM
  package in `<queries>`. A wrong guess drops the user on an unrelated screen
  or nothing, so the app links to the maintained instructions instead.
- **Detecting whether an OEM manager is active or has killed the app.** No
  public API reports it.
- **Exemption via official APIs.** The only one is the battery-optimisation
  exemption the app already requests. Samsung has stated that from One UI 6.0,
  foreground services of apps targeting Android 14 work as intended when they
  follow the new FGS policy
  ([Android Developers Blog, May 2023](https://android-developers.googleblog.com/2023/05/improving-consistency-of-background-work-on-android.html)).
  Walkable's location FGS follows it.
