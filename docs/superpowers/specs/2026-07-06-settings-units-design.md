# Units setting (System default / Kilometers / Miles) — design

Date: 2026-07-06
Status: approved pending user review

## Goal

Add a third setting to the settings page: a units override (Kilometers /
Miles / System default) that converts every distance and pace display in
the app.

## Decisions (made with user)

- Model: **system default + explicit override**, like language and theme.
  "System default" infers the unit system from the DEVICE locale's country
  code — not the app-language override (a Dane using the English UI still
  wants km).
- Imperial countries: `US`, `GB`, `LR`, `MM`; everything else metric.
- Danish label for miles is "Miles", NOT "mil" (Scandinavian mil = 10 km).
- Conversion lives in `WalkStats` (the canonical stats point); screens
  stay dumb.
- Implementation style: TDD, red-green-refactor.
- Branch: `feature/settings-units` off main (PRs #23/#24 merged).

## 1. Model (`lib/units.dart`, new file)

```dart
enum UnitSystem { metric, imperial }

/// Unit system implied by a device locale. Imperial only for the few
/// countries that use miles (US, GB, LR, MM); metric otherwise, including
/// when the locale has no country code.
UnitSystem unitSystemForLocale(Locale locale) { ... }
```

Pure and synchronous — trivially unit-testable.

## 2. Persistence & controller

`SettingsRepository` (enum-typed API, string encoding private — same
contract as theme):

- `UnitSystem? readUnitsOverride()` — prefs key `units_override`, values
  `'metric'`/`'imperial'`; absent, unknown, or corrupt (read throws) →
  null (= follow system). Never throws.
- `Future<void> writeUnitsOverride(UnitSystem? units)` — null removes the
  key; else stores `units.name`.

`SettingsController`:

- `UnitSystem? get unitsOverride` (null = follow system; mirrors
  `localeOverride`)
- `load()` additionally restores it (alongside the theme restore, before
  the locale early-return path).
- `Future<void> setUnitsOverride(UnitSystem? units)` — updates, notifies,
  persists best-effort (write failure keeps the in-memory value for the
  session).

## 3. Resolution

Screens compute the effective system in `build`:

```dart
final units = settingsController.unitsOverride ??
    unitSystemForLocale(WidgetsBinding.instance.platformDispatcher.locale);
```

Live updates come from the existing controller-rebuild wiring. Widget
tests control the device locale via
`tester.platformDispatcher.localeTestValue`.

## 4. Conversion in `WalkStats`

- `double get distanceMiles` (metres / 1609.344)
- `String formattedDistance(UnitSystem units)` — km or miles, 2 decimals.
  (Signature change from the current zero-arg method; all call sites are
  updated in this feature.)
- `double paceMinPerUnit(UnitSystem units)` — min/km, or min/mile
  (`paceMinPerKm * 1.609344`). The sentinels pass through unchanged
  (infinity stays infinity, 0.0 stays 0.0).
- `String formattedPace(UnitSystem units, {required String fallback})` —
  formats `paceMinPerUnit`; sentinels render the fallback as today.

Unit LABELS stay in the screens/l10n, not in WalkStats:

- l10n gains `unitMi` ("{value} mi", same in da) beside the existing
  `unitKm`.
- The bottom panel's inline `'km'` / `'/km'` unit strings become
  unit-dependent (`'mi'` / `'/mi'` under imperial).
- Detail screen's `'$pace /km'` likewise.

## 5. Screen threading

`WalkHistoryScreen` and `WalkDetailScreen` gain a required
`SettingsController settingsController` constructor param (matching the
DI style). Callers updated: the menu push in
`lib/screens/active_walk_screen.dart`, the `/walk-detail` route in
`lib/main.dart`, and the history→detail push inside
`walk_history_screen.dart`. Integration tests updated for the new params.

## 6. Settings UI

Third section below Theme, same shape: `_SectionHeader(l10n.settingsUnits)`
+ `RadioGroup<UnitSystem?>` with three tiles:

- **System default** → null (key `units_system`, reuses
  `settingsSystemDefault`)
- **Kilometers** → `UnitSystem.metric` (key `units_km`)
- **Miles** → `UnitSystem.imperial` (key `units_mi`)

New l10n keys (en/da): `settingsUnits` ("Units"/"Enheder"),
`unitsKilometers` ("Kilometers"/"Kilometer"), `unitsMiles`
("Miles"/"Miles").

## 7. Testing (TDD — tests written first per unit)

- **Unit** (`test/units_test.dart`): `unitSystemForLocale` for US/GB/LR/MM
  → imperial; DK/DE/no-country → metric.
- **Unit** (`test/walk_stats_test.dart`, extend): imperial distance and
  pace conversion; pace sentinels (zero distance, null duration, zero
  duration) unaffected by unit.
- **Unit** (`test/settings_controller_test.dart`, extend): restore
  default/persisted/unknown/corrupt; set + notify + persist; null clears;
  write failure keeps value.
- **Widget** (`test/screens/settings_screen_test.dart`, extend): three
  units radios; tapping Miles persists `'imperial'`; Danish strings.
- **Widget** (screen tests, extend): bottom panel shows `mi`/`/mi` under
  imperial; history tile and detail screen render converted values.
- **App-level** (`test/widget_test.dart`, extend): picking Miles flips
  the bottom panel units live; persisted `'imperial'` starts in miles;
  device locale `en_US` with no override shows miles, `da_DK` shows km.
- L10n parity is automatic.

## Out of scope

- Converting stored data (walks stay in metres — display-only feature).
- Yards/feet elevation, temperature, or any further unit classes.
