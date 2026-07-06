# Units Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a units override setting (System default / Kilometers / Miles) that converts every distance and pace display in the app.

**Architecture:** A pure `UnitSystem` model with locale-based default resolution (`lib/units.dart`), persisted override in the existing `SettingsRepository`/`SettingsController` (enum-typed, key `units_override`, absent = system), unit-aware formatting centralized in `WalkStats`, and a `SettingsController` threaded into the two screens that don't have it yet. Effective units are resolved per-build from `unitsOverride ?? unitSystemForLocale(device locale)` so changes apply live through the existing rebuild wiring.

**Tech Stack:** Flutter 3.44 / Material 3, shared_preferences, gen-l10n, flutter_test + mocktail.

**Spec:** `docs/superpowers/specs/2026-07-06-settings-units-design.md`

## Global Constraints

- Flutter binary: `/home/alexander/fvm/versions/3.44.0/bin/flutter` (flutter is NOT on PATH — use this full path everywhere `flutter` appears below).
- Work on branch `feature/settings-units` (already created, spec committed).
- TDD red-green-refactor: every task writes the failing test first and shows it fail before implementing.
- `flutter analyze` must stay clean; use `RadioGroup` (per-tile `groupValue`/`onChanged` is deprecated in Flutter 3.44).
- Units API is enum-typed end to end: no String unit values outside `SettingsRepository`'s private encoding.
- Prefs key is exactly `units_override`; values `'metric'`/`'imperial'`; absent (or unknown/corrupt) = follow system, encoded as null. `readUnitsOverride()` never throws.
- Imperial countries are exactly `US`, `GB`, `LR`, `MM` (device-locale country code); metric otherwise, including no country code.
- "System default" resolution uses the DEVICE locale (`WidgetsBinding.instance.platformDispatcher.locale`), NOT the app-language override.
- Danish label for miles is "Miles" — never "mil" (Scandinavian mil = 10 km).
- 1 mile = 1609.344 metres. Stored walk data stays in metres; this feature is display-only.
- New l10n keys in BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_da.arb`; regenerate with `flutter gen-l10n` and commit the generated `lib/l10n/app_localizations*.dart`.

---

### Task 1: UnitSystem model + locale resolution

**Files:**
- Create: `lib/units.dart`
- Test: `test/units_test.dart` (new)

**Interfaces:**
- Consumes: nothing (pure Dart + `dart:ui` Locale).
- Produces: `enum UnitSystem { metric, imperial }` and `UnitSystem unitSystemForLocale(Locale locale)` — every later task imports `package:walkable/units.dart` for these.

- [ ] **Step 1: Write the failing tests**

Create `test/units_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/units_test.dart`
Expected: FAIL — compile error, `package:walkable/units.dart` doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `lib/units.dart`:

```dart
import 'dart:ui';

/// Which measurement system distances and paces are displayed in. Walk data
/// itself is always stored in metres; this only affects formatting.
enum UnitSystem { metric, imperial }

const _imperialCountries = {'US', 'GB', 'LR', 'MM'};

/// The unit system implied by a device locale: imperial only for the few
/// countries that use miles, metric otherwise (including locales with no
/// country code).
UnitSystem unitSystemForLocale(Locale locale) =>
    _imperialCountries.contains(locale.countryCode?.toUpperCase())
        ? UnitSystem.imperial
        : UnitSystem.metric;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/units_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Analyze and commit**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter analyze`
Expected: No issues found.

```bash
git add lib/units.dart test/units_test.dart
git commit -m "feat: unit system model with locale-based default"
```

---

### Task 2: Persisted units override in repository + controller

**Files:**
- Modify: `lib/repository/settings_repository.dart`
- Modify: `lib/settings_controller.dart`
- Test: `test/settings_controller_test.dart`

**Interfaces:**
- Consumes: `UnitSystem` from Task 1; existing `SettingsRepository`/`SettingsController` and the test file's `buildController(Map<String, Object>)` helper + `MockSettingsRepository`.
- Produces (later tasks rely on these exact members):
  - `UnitSystem? SettingsRepository.readUnitsOverride()` — never throws; absent/unknown/corrupt → null
  - `Future<void> SettingsRepository.writeUnitsOverride(UnitSystem? units)` — null removes the key
  - `UnitSystem? SettingsController.unitsOverride` (getter; null = follow system)
  - `Future<void> SettingsController.setUnitsOverride(UnitSystem? units)`

- [ ] **Step 1: Write the failing tests**

Add to `test/settings_controller_test.dart` — import at the top:

```dart
import 'package:walkable/units.dart';
```

and a new group inside `main()`:

```dart
  group('unitsOverride', () {
    test('defaults to null (system) when nothing is stored', () async {
      final controller = await buildController({});
      controller.load();
      expect(controller.unitsOverride, isNull);
    });

    test('restores a persisted imperial override', () async {
      final controller = await buildController({'units_override': 'imperial'});
      controller.load();
      expect(controller.unitsOverride, UnitSystem.imperial);
    });

    test('unknown stored value -> system', () async {
      final controller = await buildController({'units_override': 'nautical'});
      controller.load();
      expect(controller.unitsOverride, isNull);
    });

    test('type-corrupt stored value -> system', () async {
      final controller = await buildController({'units_override': 42});
      controller.load();
      expect(controller.unitsOverride, isNull);
    });

    test('setUnitsOverride updates, notifies, and persists', () async {
      final controller = await buildController({});
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.setUnitsOverride(UnitSystem.imperial);

      expect(controller.unitsOverride, UnitSystem.imperial);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('units_override'), 'imperial');
    });

    test('null clears the stored value (back to system)', () async {
      final controller = await buildController({'units_override': 'metric'});
      controller.load();

      await controller.setUnitsOverride(null);

      expect(controller.unitsOverride, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('units_override'), isNull);
    });

    test('persistence failure keeps the in-memory value', () async {
      final repository = MockSettingsRepository();
      when(() => repository.writeUnitsOverride(any()))
          .thenThrow(Exception('disk full'));
      final controller = SettingsController(repository);

      await controller.setUnitsOverride(UnitSystem.metric);

      expect(controller.unitsOverride, UnitSystem.metric);
    });
  });
```

(`writeUnitsOverride(any())` — the param is nullable, so `any()` needs no `registerFallbackValue`.)

Also: the existing test `'read failure -> follows system'` in the `load` group stubs a `MockSettingsRepository` for `load()`. `load()` will now also call `readUnitsOverride()`; add this stub to that test alongside its existing `readThemeMode` stub:

```dart
      when(() => repository.readUnitsOverride()).thenReturn(null);
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/settings_controller_test.dart`
Expected: FAIL — compile errors (`unitsOverride`, `setUnitsOverride`, `readUnitsOverride`, `writeUnitsOverride` don't exist).

- [ ] **Step 3: Write the implementation**

In `lib/repository/settings_repository.dart`, add the import:

```dart
import 'package:walkable/units.dart';
```

and inside the class, after `writeThemeMode`:

```dart
  static const _unitsKey = 'units_override';

  /// The persisted units override, or null to follow the system (derived
  /// from the device locale). Absent, unknown, or corrupt data all mean
  /// null — this never throws.
  UnitSystem? readUnitsOverride() {
    String? name;
    try {
      name = _prefs.getString(_unitsKey);
    } catch (_) {
      return null; // corrupt/typed data -> follow system
    }
    return switch (name) {
      'metric' => UnitSystem.metric,
      'imperial' => UnitSystem.imperial,
      _ => null,
    };
  }

  Future<void> writeUnitsOverride(UnitSystem? units) async {
    if (units == null) {
      await _prefs.remove(_unitsKey);
    } else {
      await _prefs.setString(_unitsKey, units.name);
    }
  }
```

In `lib/settings_controller.dart`, add the import:

```dart
import 'package:walkable/units.dart';
```

the field/getter after `themeMode`:

```dart
  UnitSystem? _unitsOverride;

  UnitSystem? get unitsOverride => _unitsOverride;
```

restore it in `load()` right after the theme line (before the locale `try`, whose early returns must not skip it):

```dart
    _themeMode = repository.readThemeMode();
    _unitsOverride = repository.readUnitsOverride();
```

and the setter after `setThemeMode`:

```dart
  Future<void> setUnitsOverride(UnitSystem? units) async {
    _unitsOverride = units;
    notifyListeners();
    try {
      await repository.writeUnitsOverride(units);
    } catch (_) {
      // The choice still applies this session; it just won't survive a
      // restart.
    }
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/settings_controller_test.dart`
Expected: PASS (all, including pre-existing locale/theme groups).

- [ ] **Step 5: Analyze and commit**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter analyze`
Expected: No issues found.

```bash
git add lib/repository/settings_repository.dart lib/settings_controller.dart test/settings_controller_test.dart
git commit -m "feat: persisted units override in settings controller"
```

---

### Task 3: Unit-aware formatting in WalkStats

**Files:**
- Modify: `lib/walk_stats.dart`
- Modify (mechanical call-site updates, behavior unchanged): `lib/screens/active_walk_screen.dart` (~lines 564, 577), `lib/screens/walk_detail_screen.dart` (~lines 84, 92), `lib/screens/walk_history_screen.dart` (~lines 149, 161)
- Test: `test/walk_stats_test.dart`

**Interfaces:**
- Consumes: `UnitSystem` from Task 1.
- Produces (Task 4 relies on these exact members):
  - `double WalkStats.distanceMiles`
  - `String WalkStats.formattedDistance(UnitSystem units)` (SIGNATURE CHANGE from zero-arg)
  - `double WalkStats.paceMinPerUnit(UnitSystem units)`
  - `String WalkStats.formattedPace(UnitSystem units, {required String fallback})` (SIGNATURE CHANGE)

In THIS task, all three screens' call sites are updated mechanically to pass `UnitSystem.metric` so behavior is unchanged and everything compiles; Task 4 replaces those literals with the real resolved value.

- [ ] **Step 1: Write the failing tests**

Add to `test/walk_stats_test.dart` — import at the top:

```dart
import 'package:walkable/units.dart';
```

and a new group inside `main()` (follow the file's existing fixture style for constructing `WalkStats`; use `WalkStats(distanceMetres: ..., duration: ...)` directly):

```dart
  group('imperial units', () {
    test('distanceMiles converts from metres', () {
      const stats = WalkStats(
        distanceMetres: 1609.344,
        duration: Duration(minutes: 10),
      );
      expect(stats.distanceMiles, closeTo(1.0, 0.0001));
    });

    test('formattedDistance formats per unit system', () {
      const stats = WalkStats(
        distanceMetres: 3218.688, // 2 miles, ~3.22 km
        duration: Duration(minutes: 40),
      );
      expect(stats.formattedDistance(UnitSystem.metric), '3.22');
      expect(stats.formattedDistance(UnitSystem.imperial), '2.00');
    });

    test('paceMinPerUnit scales pace to min per mile', () {
      const stats = WalkStats(
        distanceMetres: 1609.344, // 1 mile in 16 min -> 16 min/mi
        duration: Duration(minutes: 16),
      );
      expect(stats.paceMinPerUnit(UnitSystem.imperial), closeTo(16.0, 0.001));
      expect(stats.paceMinPerUnit(UnitSystem.metric),
          closeTo(16.0 / 1.609344, 0.001));
    });

    test('pace sentinels pass through unchanged in imperial', () {
      const zeroDistance = WalkStats(
        distanceMetres: 0,
        duration: Duration(minutes: 5),
      );
      expect(zeroDistance.paceMinPerUnit(UnitSystem.imperial), double.infinity);

      const noDuration = WalkStats(distanceMetres: 1000, duration: null);
      expect(noDuration.paceMinPerUnit(UnitSystem.imperial), double.infinity);

      const zeroDuration = WalkStats(
        distanceMetres: 1000,
        duration: Duration.zero,
      );
      expect(zeroDuration.paceMinPerUnit(UnitSystem.imperial), 0.0);
      expect(zeroDuration.formattedPace(UnitSystem.imperial, fallback: '--'),
          '--');
    });
  });
```

Also update every EXISTING call of `formattedDistance()` / `formattedPace(fallback: ...)` in this test file to pass `UnitSystem.metric` as the first argument (the expected strings don't change).

- [ ] **Step 2: Run tests to verify they fail**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/walk_stats_test.dart`
Expected: FAIL — compile errors (`distanceMiles`, `paceMinPerUnit` don't exist; changed signatures).

- [ ] **Step 3: Write the implementation**

In `lib/walk_stats.dart`, add the import:

```dart
import 'package:walkable/units.dart';
```

and replace the formatting members (from `distanceKm` down) with:

```dart
  static const _metresPerMile = 1609.344;

  double get distanceKm => distanceMetres / 1000;

  double get distanceMiles => distanceMetres / _metresPerMile;

  /// Pace in min/km. Carries [calc.pace]'s sentinels: infinity for zero
  /// distance or unknown duration, 0.0 for zero duration.
  double get paceMinPerKm =>
      duration == null ? double.infinity : calc.pace(distanceMetres, duration!);

  /// Pace in minutes per display unit (km or mile). The sentinels pass
  /// through unchanged (infinity stays infinity, 0.0 stays 0.0).
  double paceMinPerUnit(UnitSystem units) => units == UnitSystem.metric
      ? paceMinPerKm
      : paceMinPerKm * (_metresPerMile / 1000);

  /// Distance in the display unit to two decimals (e.g. `"1.23"`).
  String formattedDistance(UnitSystem units) =>
      (units == UnitSystem.metric ? distanceKm : distanceMiles)
          .toStringAsFixed(2);

  /// Duration as `h:mm:ss`, or `m:ss` when under an hour. Returns [fallback]
  /// when the duration is unknown.
  String formattedDuration({required String fallback}) {
    final d = duration;
    if (d == null) return fallback;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  /// Pace as `m:ss` in the display unit, or [fallback] for the unavailable
  /// sentinels.
  String formattedPace(UnitSystem units, {required String fallback}) =>
      calc.formatPace(paceMinPerUnit(units), fallback: fallback);
```

Then fix the three screens' call sites mechanically (behavior unchanged — Task 4 does the real wiring). Add `import 'package:walkable/units.dart';` to each file:

`lib/screens/active_walk_screen.dart` (in `_buildActive`):
- `stats.formattedDistance()` → `stats.formattedDistance(UnitSystem.metric)`
- `stats.formattedPace(fallback: l10n.paceUnavailable)` → `stats.formattedPace(UnitSystem.metric, fallback: l10n.paceUnavailable)`

`lib/screens/walk_detail_screen.dart` (in `_StatsPanel.build`):
- `stats.formattedPace(fallback: l10n.paceUnavailable)` → `stats.formattedPace(UnitSystem.metric, fallback: l10n.paceUnavailable)`
- `stats.formattedDistance()` → `stats.formattedDistance(UnitSystem.metric)`

`lib/screens/walk_history_screen.dart` (in `_WalkCard.build`):
- `stats.formattedDistance()` → `stats.formattedDistance(UnitSystem.metric)`
- `stats.formattedPace(fallback: l10n.paceUnavailable)` → `stats.formattedPace(UnitSystem.metric, fallback: l10n.paceUnavailable)`

- [ ] **Step 4: Run the full suite to verify everything passes**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test`
Expected: PASS (full suite — screens behave identically with the metric literal).

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter analyze`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/walk_stats.dart lib/screens/ test/walk_stats_test.dart
git commit -m "feat: unit-aware distance and pace formatting in WalkStats"
```

---

### Task 4: Display walk stats in the user's unit system

**Files:**
- Modify: `lib/screens/active_walk_screen.dart` (resolve units; thread into `_BottomPanel`; pass controller to `WalkHistoryScreen`)
- Modify: `lib/screens/walk_history_screen.dart` (new `settingsController` param; thread into `_WalkCard`)
- Modify: `lib/screens/walk_detail_screen.dart` (new `settingsController` param; thread into `_StatsPanel`)
- Modify: `lib/main.dart` (`/walk-detail` route passes the controller)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_da.arb` (+ regenerated files): add `unitMi`
- Test: `test/screens/active_walk_screen_test.dart`, `test/screens/walk_history_screen_test.dart`, `test/screens/walk_detail_screen_test.dart`

**Interfaces:**
- Consumes: `unitsOverride` (Task 2), `unitSystemForLocale` (Task 1), unit-aware `WalkStats` methods (Task 3).
- Produces: `WalkHistoryScreen({required WalkRepository repository, required SettingsController settingsController})` and `WalkDetailScreen({required Walk walk, required SettingsController settingsController})` — Task 5's app-level tests rely on the whole chain compiling. L10n getter `unitMi`.

The resolution expression used in all three screens (compute in `build` so setting changes apply live):

```dart
    final units = settingsController.unitsOverride ??
        unitSystemForLocale(WidgetsBinding.instance.platformDispatcher.locale);
```

(with `widget.settingsController` in State classes.)

- [ ] **Step 1: Add the l10n key**

`lib/l10n/app_en.arb` — after the `"unitKm"` entry's `@unitKm` block, add:

```json
  "unitMi": "{value} mi",
  "@unitMi": {
    "placeholders": {
      "value": { "type": "String" }
    }
  }
```

`lib/l10n/app_da.arb` — after the `"unitKm"` line, add:

```json
  "unitMi": "{value} mi"
```

(Mind the trailing-comma placement — these files are JSON; the previous last entry gains a comma.)

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter gen-l10n` then `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/l10n_parity_test.dart`
Expected: both succeed.

- [ ] **Step 2: Write the failing widget tests**

All three screen test files construct their screens directly; each needs a real `SettingsController`. In EACH of the three files, add imports:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/settings_controller.dart';
```

(skip any already present — `active_walk_screen_test.dart` has all three already).

**`test/screens/walk_history_screen_test.dart`:** its `buildSubject`-style helper must create and pass a controller. Mirror this shape (adapt to the file's actual helper name and params):

```dart
  late SettingsController settingsController;

  Future<Widget> buildSubject() async {
    SharedPreferences.setMockInitialValues(prefsValues);
    final prefs = await SharedPreferences.getInstance();
    settingsController = SettingsController(SettingsRepository(prefs))..load();
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WalkHistoryScreen(
        repository: mockRepository,
        settingsController: settingsController,
      ),
    );
  }
```

where `prefsValues` is a `Map<String, Object>` the test sets (default `{}`). Update all existing pump call sites for the new signature. Add one new test (reuse the file's existing walk fixture that has a known distance):

```dart
  testWidgets('shows miles when the imperial override is set', (tester) async {
    // Fixture: a walk with distanceMetres 1609.344 (1 mile / 1.61 km).
    // Adapt the fixture construction to this file's existing Walk fixtures.
    prefsValues = {'units_override': 'imperial'};
    when(() => mockRepository.findAll()).thenAnswer((_) async => [walkFixture]);

    await tester.pumpWidget(await buildSubject());
    await tester.pumpAndSettle();

    expect(find.textContaining('1.00 mi'), findsOneWidget);
    expect(find.textContaining('km'), findsNothing);
  });
```

**`test/screens/walk_detail_screen_test.dart`:** same controller-threading change to its helper (screen param: `settingsController`), plus:

```dart
  testWidgets('shows miles and /mi pace when the imperial override is set',
      (tester) async {
    // Fixture: walk with distanceMetres 1609.344 and duration 16 min.
    prefsValues = {'units_override': 'imperial'};

    await tester.pumpWidget(await buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('1.00 mi'), findsOneWidget);
    expect(find.text('16:00 /mi'), findsOneWidget);
  });
```

**`test/screens/active_walk_screen_test.dart`:** the file already has recording-state tests that push a `WalkSnapshot` with stats. Add two tests following that existing snapshot-pumping pattern (reuse its helpers for entering the recording state with a snapshot whose distance is 1609.344 m over 16 min):

```dart
  testWidgets('bottom panel shows mi units under the imperial override',
      (tester) async {
    // (enter recording state with the 1-mile snapshot, per the file's
    // existing pattern; prefs seeded with {'units_override': 'imperial'})
    expect(find.text('1.00'), findsOneWidget);
    expect(find.textContaining('mi'), findsWidgets);
    expect(find.textContaining('/mi'), findsOneWidget);
  });

  testWidgets('system default units follow the device locale', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    // (no units_override in prefs; enter recording state with the same
    // 1-mile snapshot)
    expect(find.textContaining('/mi'), findsOneWidget);
  });
```

Note on assertion style: the bottom panel renders the unit inside a `RichText` (`_StatBlock`), so plain `find.text` may not match the unit suffix — `find.textContaining` with `findRichText: true` (`find.textContaining('mi', findRichText: true)`) is the reliable form; use it if the plain finder fails.

- [ ] **Step 3: Run tests to verify they fail**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/screens/`
Expected: FAIL — compile errors (`settingsController` params don't exist on the two screens).

- [ ] **Step 4: Implement the threading and display**

1. `lib/screens/walk_history_screen.dart`:
   - imports: add `package:walkable/settings_controller.dart` and `package:walkable/units.dart` (units already imported by Task 3).
   - Constructor:

```dart
class WalkHistoryScreen extends StatefulWidget {
  final WalkRepository repository;
  final SettingsController settingsController;

  const WalkHistoryScreen({
    super.key,
    required this.repository,
    required this.settingsController,
  });
```

   - In `_WalkHistoryScreenState.build`, before `return Scaffold(`:

```dart
    final units = widget.settingsController.unitsOverride ??
        unitSystemForLocale(WidgetsBinding.instance.platformDispatcher.locale);
```

   - Pass to the card: `_WalkCard(walk: walk, units: units, onTap: ...)`; `_WalkCard` gains `final UnitSystem units;` (constructor param), and its stats row becomes:

```dart
                  _Stat(
                    value: units == UnitSystem.metric
                        ? l10n.unitKm(stats.formattedDistance(units))
                        : l10n.unitMi(stats.formattedDistance(units)),
                    label: l10n.statDistance,
                    emphasized: true,
                  ),
```

   and the pace stat: `stats.formattedPace(units, fallback: l10n.paceUnavailable)`.

2. `lib/screens/walk_detail_screen.dart`:
   - imports: add `package:walkable/settings_controller.dart`.
   - Constructor:

```dart
class WalkDetailScreen extends StatelessWidget {
  final Walk walk;
  final SettingsController settingsController;

  const WalkDetailScreen({
    super.key,
    required this.walk,
    required this.settingsController,
  });
```

   - In `build`, resolve `units` (expression above, using `settingsController` directly) and pass down: `_StatsPanel(stats: stats, units: units)`; `_StatsPanel` gains `final UnitSystem units;`, and its body becomes:

```dart
    final pace = stats.formattedPace(units, fallback: l10n.paceUnavailable);
    final paceUnit = units == UnitSystem.metric ? '/km' : '/mi';
    ...
          _StatItem(
            label: l10n.statDistance,
            value: units == UnitSystem.metric
                ? l10n.unitKm(stats.formattedDistance(units))
                : l10n.unitMi(stats.formattedDistance(units)),
          ),
    ...
          _StatItem(
            label: l10n.statPace,
            value: stats.paceMinPerKm.isFinite ? '$pace $paceUnit' : pace,
          ),
```

3. `lib/screens/active_walk_screen.dart`:
   - In `_ActiveWalkScreenState.build`, resolve `units` (expression above with `widget.settingsController`) and pass `units: units` to `_BottomPanel`.
   - `_BottomPanel` gains `final UnitSystem units;` (constructor param). In `_buildActive`:

```dart
              _StatBlock(
                label: l10n.statDistance,
                value: stats.formattedDistance(widget.units),
                unit: widget.units == UnitSystem.metric ? 'km' : 'mi',
              ),
    ...
              _StatBlock(
                label: l10n.statPace,
                value: stats.formattedPace(widget.units,
                    fallback: l10n.paceUnavailable),
                unit: stats.paceMinPerKm.isFinite
                    ? (widget.units == UnitSystem.metric ? '/km' : '/mi')
                    : null,
              ),
```

   - The menu's History item now passes the controller:

```dart
                      WalkHistoryScreen(
                        repository: widget.repository,
                        settingsController: widget.settingsController,
                      ),
```

4. `lib/main.dart` — the `/walk-detail` route:

```dart
            return MaterialPageRoute(
              builder: (_) => WalkDetailScreen(
                walk: walk,
                settingsController: settingsController,
              ),
            );
```

- [ ] **Step 5: Run the full suite to verify everything passes**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test`
Expected: PASS. If `integration_test/*.dart` fails to compile (it constructs screens directly), add the controller param there the same way — check with:
`grep -rn "WalkHistoryScreen(\|WalkDetailScreen(" integration_test/`

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter analyze`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add lib/ test/ integration_test/
git commit -m "feat: display walk stats in the user's unit system"
```

---

### Task 5: Units section on the settings screen

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_da.arb` (+ regenerated files)
- Modify: `lib/screens/settings_screen.dart`
- Test: `test/screens/settings_screen_test.dart`, `test/widget_test.dart`

**Interfaces:**
- Consumes: `unitsOverride`/`setUnitsOverride` (Task 2), `UnitSystem` (Task 1), `_SectionHeader` (existing), `settingsSystemDefault` (existing, reused).
- Produces: radio tile keys `units_system`, `units_km`, `units_mi`; l10n getters `settingsUnits`, `unitsKilometers`, `unitsMiles`.

- [ ] **Step 1: Add l10n keys**

`lib/l10n/app_en.arb`, after `"themeDark"`:

```json
  "settingsUnits": "Units",
  "unitsKilometers": "Kilometers",
  "unitsMiles": "Miles",
```

`lib/l10n/app_da.arb`, after `"themeDark"`:

```json
  "settingsUnits": "Enheder",
  "unitsKilometers": "Kilometer",
  "unitsMiles": "Miles",
```

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter gen-l10n` then `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/l10n_parity_test.dart`
Expected: both succeed.

- [ ] **Step 2: Write the failing tests**

In `test/screens/settings_screen_test.dart` — add import `package:walkable/units.dart`. "System default" now appears THREE times; update the two count assertions:

- in `'shows language section with the three options'`: `findsNWidgets(2)` → `findsNWidgets(3)` (comment: `// language + theme + units`)
- in `'renders Danish strings under the Danish locale'`: `findsNWidgets(2)` → `findsNWidgets(3)`

Add new tests at the end of `main()`:

```dart
  testWidgets('shows units section with the three options', (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    expect(find.text('Units'), findsOneWidget);
    expect(find.text('Kilometers'), findsOneWidget);
    expect(find.text('Miles'), findsOneWidget);
  });

  testWidgets('system units selected when there is no override',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    final group = tester
        .widget<RadioGroup<UnitSystem?>>(find.byType(RadioGroup<UnitSystem?>));
    expect(group.groupValue, isNull);
  });

  testWidgets('tapping Miles updates the controller and persists',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    await tester.scrollUntilVisible(
        find.byKey(const Key('units_mi')), 100);
    await tester.tap(find.byKey(const Key('units_mi')));
    await tester.pumpAndSettle();

    expect(controller.unitsOverride, UnitSystem.imperial);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('units_override'), 'imperial');
  });

  testWidgets('tapping System default clears the units override',
      (tester) async {
    await setUpController({'units_override': 'imperial'});
    await tester.pumpWidget(buildSubject());

    await tester.scrollUntilVisible(
        find.byKey(const Key('units_system')), 100);
    await tester.tap(find.byKey(const Key('units_system')));
    await tester.pumpAndSettle();

    expect(controller.unitsOverride, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('units_override'), isNull);
  });

  testWidgets('renders Danish units strings under the Danish locale',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject(locale: const Locale('da')));

    expect(find.text('Enheder'), findsOneWidget);
    expect(find.text('Kilometer'), findsOneWidget);
    expect(find.text('Miles'), findsOneWidget);
  });
```

(`scrollUntilVisible`: with three sections the units tiles may sit below the test viewport fold; scrolling first makes the taps reliable. If the page fits, the scroll is a no-op.)

In `test/widget_test.dart` — add import `package:walkable/units.dart`, then append:

```dart
  testWidgets('selecting Miles persists the imperial override',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settingsController = SettingsController(SettingsRepository(prefs))
      ..load();

    await tester.pumpWidget(
      WalkableApp(
        recorder: recorder,
        repository: repository,
        settingsController: settingsController,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('units_mi')), 100);
    await tester.tap(find.byKey(const Key('units_mi')));
    await tester.pumpAndSettle();

    expect(settingsController.unitsOverride, UnitSystem.imperial);
    expect(prefs.getString('units_override'), 'imperial');
  });

  testWidgets('starts with the imperial override when persisted',
      (tester) async {
    SharedPreferences.setMockInitialValues({'units_override': 'imperial'});
    final prefs = await SharedPreferences.getInstance();
    final settingsController = SettingsController(SettingsRepository(prefs))
      ..load();

    await tester.pumpWidget(
      WalkableApp(
        recorder: recorder,
        repository: repository,
        settingsController: settingsController,
      ),
    );
    await tester.pumpAndSettle();

    expect(settingsController.unitsOverride, UnitSystem.imperial);
  });
```

(Live display conversion is covered by Task 4's screen tests; these verify the end-to-end selection/persistence path through the real UI.)

- [ ] **Step 3: Run tests to verify they fail**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/screens/settings_screen_test.dart test/widget_test.dart`
Expected: FAIL — units section/keys don't exist; count assertions off.

- [ ] **Step 4: Implement the units section**

In `lib/screens/settings_screen.dart` — add import:

```dart
import 'package:walkable/units.dart';
```

and append a third section inside the `ListView` children, after the theme `RadioGroup`:

```dart
            _SectionHeader(l10n.settingsUnits),
            RadioGroup<UnitSystem?>(
              groupValue: controller.unitsOverride,
              onChanged: controller.setUnitsOverride,
              child: Column(
                children: [
                  RadioListTile<UnitSystem?>(
                    key: const Key('units_system'),
                    value: null,
                    title: Text(l10n.settingsSystemDefault),
                  ),
                  RadioListTile<UnitSystem?>(
                    key: const Key('units_km'),
                    value: UnitSystem.metric,
                    title: Text(l10n.unitsKilometers),
                  ),
                  RadioListTile<UnitSystem?>(
                    key: const Key('units_mi'),
                    value: UnitSystem.imperial,
                    title: Text(l10n.unitsMiles),
                  ),
                ],
              ),
            ),
```

- [ ] **Step 5: Run the full suite to verify everything passes**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test`
Expected: PASS (full suite).

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter analyze`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/ lib/screens/settings_screen.dart test/screens/settings_screen_test.dart test/widget_test.dart
git commit -m "feat: units section on the settings screen"
```

---

## Done criteria

- Full test suite and `flutter analyze` pass.
- Manual smoke (optional): Settings → Miles converts bottom panel, history cards, and detail stats instantly; System default shows km on a Danish device and mi with device language English (US); relaunch keeps the choice.
- Push `feature/settings-units` and open a PR against main.
