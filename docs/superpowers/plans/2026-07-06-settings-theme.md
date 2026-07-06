# Theme Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a theme override setting (System default / Light / Dark) to the settings page, persisted across restarts and applied instantly.

**Architecture:** Extends the existing settings stack: `SettingsRepository` gains an enum-typed `ThemeMode` read/write pair (prefs key `theme_mode`, string encoding private to the repository), `SettingsController` gains `themeMode`/`setThemeMode`, `SettingsScreen` gains a second `RadioGroup` section, and `MaterialApp.themeMode` (already inside a `ListenableBuilder`) switches from the hardcoded `ThemeMode.system` to the controller value.

**Tech Stack:** Flutter 3.44 / Material 3, shared_preferences, gen-l10n, flutter_test + mocktail.

**Spec:** `docs/superpowers/specs/2026-07-06-settings-theme-design.md`

## Global Constraints

- Flutter binary: `/home/alexander/fvm/versions/3.44.0/bin/flutter` (flutter is NOT on PATH — use this full path everywhere `flutter` appears below).
- Work on branch `feature/settings-theme` (already created, spec committed).
- TDD red-green-refactor: every task writes the failing test first and shows it fail before implementing.
- `flutter analyze` must stay clean; use `RadioGroup` (per-tile `groupValue`/`onChanged` is deprecated in Flutter 3.44).
- The theme API is enum-typed end to end: no `String`/`String?` theme values outside `SettingsRepository`'s private encoding.
- Prefs key is exactly `theme_mode`; values `'light'`/`'dark'`; absent (or unknown/corrupt) = follow system. `ThemeMode.system` is stored by REMOVING the key.
- New l10n keys in BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_da.arb`; regenerate with `flutter gen-l10n` and commit the generated files. The existing `settingsSystemDefault` key is REUSED for the theme section's system option.

---

### Task 1: Theme support in SettingsRepository + SettingsController

**Files:**
- Modify: `lib/repository/settings_repository.dart`
- Modify: `lib/settings_controller.dart`
- Test: `test/settings_controller_test.dart`

**Interfaces:**
- Consumes: existing `SettingsRepository(SharedPreferences prefs)`, `SettingsController(SettingsRepository repository)`, `load()`, and the test file's existing `buildController(Map<String, Object>)` helper and `MockSettingsRepository`.
- Produces (later tasks rely on these exact members):
  - `ThemeMode SettingsRepository.readThemeMode()` — never throws; absent/unknown/corrupt → `ThemeMode.system`
  - `Future<void> SettingsRepository.writeThemeMode(ThemeMode mode)`
  - `ThemeMode SettingsController.themeMode` (getter, initial `ThemeMode.system`)
  - `Future<void> SettingsController.setThemeMode(ThemeMode mode)` — updates, notifies, persists best-effort
  - `load()` additionally restores the theme (before the locale logic, so locale corruption can't skip it)

- [ ] **Step 1: Write the failing tests**

In `test/settings_controller_test.dart`:

1. Change the flutter import (ThemeMode lives in material):

```dart
import 'package:flutter/material.dart';
```

(replacing `import 'package:flutter/widgets.dart';`)

2. mocktail needs a fallback for the non-nullable `ThemeMode` matcher. At the top of `main()`, before the groups, add:

```dart
  setUpAll(() => registerFallbackValue(ThemeMode.system));
```

3. Add a new top-level group inside `main()`:

```dart
  group('themeMode', () {
    test('defaults to system when nothing is stored', () async {
      final controller = await buildController({});
      controller.load();
      expect(controller.themeMode, ThemeMode.system);
    });

    test('restores a persisted dark override', () async {
      final controller = await buildController({'theme_mode': 'dark'});
      controller.load();
      expect(controller.themeMode, ThemeMode.dark);
    });

    test('unknown stored value -> system', () async {
      final controller = await buildController({'theme_mode': 'sepia'});
      controller.load();
      expect(controller.themeMode, ThemeMode.system);
    });

    test('type-corrupt stored value -> system', () async {
      // A non-string under the key makes SharedPreferences.getString throw;
      // readThemeMode must swallow that and follow the system.
      final controller = await buildController({'theme_mode': 42});
      controller.load();
      expect(controller.themeMode, ThemeMode.system);
    });

    test('setThemeMode updates, notifies, and persists', () async {
      final controller = await buildController({});
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.setThemeMode(ThemeMode.dark);

      expect(controller.themeMode, ThemeMode.dark);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');
    });

    test('selecting system removes the stored value', () async {
      final controller = await buildController({'theme_mode': 'dark'});
      controller.load();

      await controller.setThemeMode(ThemeMode.system);

      expect(controller.themeMode, ThemeMode.system);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), isNull);
    });

    test('persistence failure keeps the in-memory value', () async {
      final repository = MockSettingsRepository();
      when(() => repository.writeThemeMode(any()))
          .thenThrow(Exception('disk full'));
      final controller = SettingsController(repository);

      await controller.setThemeMode(ThemeMode.dark);

      expect(controller.themeMode, ThemeMode.dark);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/settings_controller_test.dart`
Expected: FAIL — compile errors (`themeMode`, `setThemeMode`, `readThemeMode`, `writeThemeMode` don't exist).

- [ ] **Step 3: Write the implementation**

In `lib/repository/settings_repository.dart`, add a material import at the top (for `ThemeMode`):

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
```

and add inside the class, after `writeLocaleCode`:

```dart
  static const _themeKey = 'theme_mode';

  /// The persisted theme override. Absent, unknown, or corrupt data all mean
  /// "follow the system" — this never throws.
  ThemeMode readThemeMode() {
    String? name;
    try {
      name = _prefs.getString(_themeKey);
    } catch (_) {
      return ThemeMode.system; // corrupt/typed data -> follow system
    }
    return switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> writeThemeMode(ThemeMode mode) async {
    if (mode == ThemeMode.system) {
      await _prefs.remove(_themeKey);
    } else {
      await _prefs.setString(_themeKey, mode.name);
    }
  }
```

In `lib/settings_controller.dart`:

1. Change the flutter import to material (for `ThemeMode`):

```dart
import 'package:flutter/material.dart';
```

2. Add the field and getter after `localeOverride`:

```dart
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;
```

3. Restore the theme at the TOP of `load()` (before the locale logic — the locale path early-returns on corrupt data and must not skip the theme):

```dart
  void load() {
    _themeMode = repository.readThemeMode();
    String? code;
    try {
      code = repository.readLocaleCode();
    } catch (_) {
      return; // corrupt/typed data -> follow system
    }
    if (code == null) return;
    final supported = AppLocalizations.supportedLocales
        .any((locale) => locale.languageCode == code);
    _localeOverride = supported ? Locale(code) : null;
  }
```

4. Add the setter after `setLocaleOverride`:

```dart
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      await repository.writeThemeMode(mode);
    } catch (_) {
      // The choice still applies this session; it just won't survive a
      // restart.
    }
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/settings_controller_test.dart`
Expected: PASS (all, including the pre-existing locale tests).

- [ ] **Step 5: Analyze and commit**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter analyze`
Expected: No issues found.

```bash
git add lib/repository/settings_repository.dart lib/settings_controller.dart test/settings_controller_test.dart
git commit -m "feat: persisted theme override in settings controller"
```

---

### Task 2: l10n keys + theme section in SettingsScreen

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_da.arb` (+ regenerated `lib/l10n/app_localizations*.dart`)
- Modify: `lib/screens/settings_screen.dart`
- Test: `test/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes: `SettingsController.themeMode` / `setThemeMode(ThemeMode)` from Task 1; existing l10n key `settingsSystemDefault`; the test file's existing `setUpController`/`buildSubject` helpers.
- Produces: theme radio tiles with keys `Key('theme_system')`, `Key('theme_light')`, `Key('theme_dark')` (Task 3 relies on `theme_dark`). L10n getters `settingsTheme`, `themeLight`, `themeDark`.

- [ ] **Step 1: Add l10n keys**

In `lib/l10n/app_en.arb`, after the `"navMenu"` line, add:

```json
  "settingsTheme": "Theme",
  "themeLight": "Light",
  "themeDark": "Dark",
```

In `lib/l10n/app_da.arb`, after the `"navMenu"` line, add:

```json
  "settingsTheme": "Tema",
  "themeLight": "Lyst",
  "themeDark": "Mørkt",
```

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter gen-l10n`
Expected: exits 0; new getters appear in `lib/l10n/app_localizations*.dart`.

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/l10n_parity_test.dart`
Expected: PASS.

- [ ] **Step 2: Write the failing widget tests**

In `test/screens/settings_screen_test.dart`:

1. The theme section reuses the "System default" label, so it now appears TWICE on the page. Update the two existing assertions that expect one:

In `'shows language section with the three options'`, change

```dart
    expect(find.text('System default'), findsOneWidget);
```

to

```dart
    expect(find.text('System default'), findsNWidgets(2)); // language + theme
```

In `'renders Danish strings under the Danish locale'`, change

```dart
    expect(find.text('Systemstandard'), findsOneWidget);
```

to

```dart
    expect(find.text('Systemstandard'), findsNWidgets(2)); // language + theme
```

2. Add new tests at the end of `main()`:

```dart
  testWidgets('shows theme section with the three options', (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('system theme is selected when there is no override',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    final group = tester
        .widget<RadioGroup<ThemeMode>>(find.byType(RadioGroup<ThemeMode>));
    expect(group.groupValue, ThemeMode.system);
  });

  testWidgets('persisted theme override is the selected radio',
      (tester) async {
    await setUpController({'theme_mode': 'dark'});
    await tester.pumpWidget(buildSubject());

    final group = tester
        .widget<RadioGroup<ThemeMode>>(find.byType(RadioGroup<ThemeMode>));
    expect(group.groupValue, ThemeMode.dark);
  });

  testWidgets('tapping Dark updates the controller and persists',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const Key('theme_dark')));
    await tester.pumpAndSettle();

    expect(controller.themeMode, ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
  });

  testWidgets('tapping System default clears the theme override',
      (tester) async {
    await setUpController({'theme_mode': 'dark'});
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const Key('theme_system')));
    await tester.pumpAndSettle();

    expect(controller.themeMode, ThemeMode.system);
  });

  testWidgets('renders Danish theme strings under the Danish locale',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject(locale: const Locale('da')));

    expect(find.text('Tema'), findsOneWidget);
    expect(find.text('Lyst'), findsOneWidget);
    expect(find.text('Mørkt'), findsOneWidget);
  });
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/screens/settings_screen_test.dart`
Expected: FAIL — the new tests can't find the theme section (`find.text('Theme')` finds nothing, `RadioGroup<ThemeMode>` doesn't exist), and the two updated assertions find 1 widget where 2 are expected.

- [ ] **Step 4: Write the implementation**

Replace `lib/screens/settings_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  final SettingsController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.screenSettings)),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(
          children: [
            _SectionHeader(l10n.settingsLanguage),
            RadioGroup<Locale?>(
              groupValue: controller.localeOverride,
              onChanged: controller.setLocaleOverride,
              child: Column(
                children: [
                  RadioListTile<Locale?>(
                    key: const Key('language_system'),
                    value: null,
                    title: Text(l10n.settingsSystemDefault),
                  ),
                  RadioListTile<Locale?>(
                    key: const Key('language_en'),
                    value: const Locale('en'),
                    title: Text(l10n.languageEnglish),
                  ),
                  RadioListTile<Locale?>(
                    key: const Key('language_da'),
                    value: const Locale('da'),
                    title: Text(l10n.languageDanish),
                  ),
                ],
              ),
            ),
            _SectionHeader(l10n.settingsTheme),
            RadioGroup<ThemeMode>(
              groupValue: controller.themeMode,
              onChanged: (mode) =>
                  controller.setThemeMode(mode ?? ThemeMode.system),
              child: Column(
                children: [
                  RadioListTile<ThemeMode>(
                    key: const Key('theme_system'),
                    value: ThemeMode.system,
                    title: Text(l10n.settingsSystemDefault),
                  ),
                  RadioListTile<ThemeMode>(
                    key: const Key('theme_light'),
                    value: ThemeMode.light,
                    title: Text(l10n.themeLight),
                  ),
                  RadioListTile<ThemeMode>(
                    key: const Key('theme_dark'),
                    value: ThemeMode.dark,
                    title: Text(l10n.themeDark),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// M3 settings-section header: primary-colored titleSmall with list-inset
/// padding. Shared by the language and theme sections.
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall!
            .copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}
```

(This also extracts the previously inline language header into `_SectionHeader` so the styling block isn't duplicated. `RadioGroup.onChanged` receives `ThemeMode?`; the `?? ThemeMode.system` keeps the controller API non-nullable.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/screens/settings_screen_test.dart test/l10n_parity_test.dart`
Expected: PASS (all).

- [ ] **Step 6: Analyze and commit**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter analyze`
Expected: No issues found.

```bash
git add lib/l10n/ lib/screens/settings_screen.dart test/screens/settings_screen_test.dart
git commit -m "feat: theme section on the settings screen"
```

---

### Task 3: Apply the theme override to MaterialApp

**Files:**
- Modify: `lib/main.dart` (the `themeMode:` line, currently `lib/main.dart:77`)
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: `SettingsController.themeMode` (Task 1); widget keys `menu_button`/`settings_button` (existing) and `theme_dark` (Task 2).
- Produces: `MaterialApp.themeMode` follows the controller live. No new symbols.

- [ ] **Step 1: Write the failing tests**

Append inside `main()` of `test/widget_test.dart` (the file already has shared mock `setUp`; these tests follow the pattern of the existing locale tests):

```dart
  testWidgets('selecting Dark switches the app theme immediately',
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
    await tester.tap(find.byKey(const Key('theme_dark')));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(prefs.getString('theme_mode'), 'dark');
  });

  testWidgets('starts dark when a dark override was persisted',
      (tester) async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
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

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/widget_test.dart`
Expected: the two new tests FAIL on the `app.themeMode` expectation (it's still the hardcoded `ThemeMode.system`); persistence assertion alone would pass, the wiring is what's missing.

- [ ] **Step 3: Wire the controller into MaterialApp**

In `lib/main.dart`, inside `WalkableApp.build`, change

```dart
        themeMode: ThemeMode.system,
```

to

```dart
        // User theme override; ThemeMode.system follows the device.
        themeMode: settingsController.themeMode,
```

(The surrounding `ListenableBuilder` from the locale work already rebuilds `MaterialApp` on controller changes — no other edit needed.)

- [ ] **Step 4: Run the full suite to verify everything passes**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test`
Expected: PASS (full suite).

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter analyze`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart test/widget_test.dart
git commit -m "feat: apply persisted theme override to the app theme"
```

---

## Done criteria

- Full test suite and `flutter analyze` pass.
- Manual smoke (optional): Settings → Dark flips the whole app (including map tiles, which follow `Theme.of(context).brightness`) instantly; relaunch stays dark; System default follows the device.
- Push `feature/settings-theme` and open a PR (target main once PR #23 is merged; otherwise stack on `feature/settings-language`).
