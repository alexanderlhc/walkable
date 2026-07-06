# Settings Page with Language Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a settings page reachable from a new main-screen menu chip, whose first setting is a language override (System default / English / Dansk) persisted across restarts.

**Architecture:** A `SettingsController` (ChangeNotifier) holding `Locale? localeOverride`, backed by a `SettingsRepository` on shared_preferences, constructor-injected from `main()` like the existing `WalkRecorder`/`WalkRepository`. A `ListenableBuilder` wraps `MaterialApp` so locale changes rebuild the app; `null` override falls through to the existing system-locale resolution. The main screen's labeled "Walk History" chip is replaced by an icon-only menu chip (`MenuAnchor`) containing History and Settings.

**Tech Stack:** Flutter 3.44 / Material 3, shared_preferences, gen-l10n (`.arb` files, generated code committed under `lib/l10n/`), flutter_test + mocktail.

**Spec:** `docs/superpowers/specs/2026-07-06-settings-language-design.md`

## Global Constraints

- Flutter binary: `/home/alexander/fvm/versions/3.44.0/bin/flutter` (flutter is NOT on PATH — use this full path everywhere `flutter` appears below).
- Work on branch `feature/settings-language` (already created).
- TDD red-green-refactor: every task writes the failing test first and shows it fail before implementing.
- Flutter 3.44 deprecates `RadioListTile.groupValue`/`onChanged` — use the `RadioGroup` widget instead. `flutter analyze` must stay clean.
- New l10n keys must be added to BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_da.arb` (existing `l10n_parity_test.dart` enforces this). Regenerate with `flutter gen-l10n` and commit the generated `lib/l10n/app_localizations*.dart` changes.
- Prefs key for the override is exactly `locale_override` (absent = follow system).

---

### Task 1: SettingsRepository + SettingsController

**Files:**
- Modify: `pubspec.yaml` (add shared_preferences)
- Create: `lib/repository/settings_repository.dart`
- Create: `lib/settings_controller.dart`
- Test: `test/settings_controller_test.dart`

**Interfaces:**
- Consumes: `AppLocalizations.supportedLocales` (existing, `package:walkable/l10n/app_localizations.dart`)
- Produces:
  - `SettingsRepository(SharedPreferences prefs)`; `String? readLocaleCode()`; `Future<void> writeLocaleCode(String? code)`
  - `SettingsController(SettingsRepository repository)` extends `ChangeNotifier`; `Locale? get localeOverride`; `void load()`; `Future<void> setLocaleOverride(Locale? locale)`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:` after `latlong2: ^0.9.0`, add:

```yaml
  shared_preferences: ^2.3.0
```

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter pub get`
Expected: resolves without errors.

- [ ] **Step 2: Write the failing tests**

Create `test/settings_controller_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/settings_controller.dart';

class MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsController> buildController(
      Map<String, Object> initialPrefs) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final prefs = await SharedPreferences.getInstance();
    return SettingsController(SettingsRepository(prefs));
  }

  group('load', () {
    test('no stored value -> follows system (null override)', () async {
      final controller = await buildController({});
      controller.load();
      expect(controller.localeOverride, isNull);
    });

    test('stored "da" -> Danish override', () async {
      final controller = await buildController({'locale_override': 'da'});
      controller.load();
      expect(controller.localeOverride, const Locale('da'));
    });

    test('unsupported stored code -> follows system', () async {
      final controller = await buildController({'locale_override': 'de'});
      controller.load();
      expect(controller.localeOverride, isNull);
    });
  });

  group('setLocaleOverride', () {
    test('updates value, notifies, and persists', () async {
      final controller = await buildController({});
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.setLocaleOverride(const Locale('da'));

      expect(controller.localeOverride, const Locale('da'));
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('locale_override'), 'da');
    });

    test('null clears the stored value (back to system)', () async {
      final controller = await buildController({'locale_override': 'da'});
      controller.load();

      await controller.setLocaleOverride(null);

      expect(controller.localeOverride, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('locale_override'), isNull);
    });

    test('persistence failure keeps the in-memory value', () async {
      final repository = MockSettingsRepository();
      when(() => repository.writeLocaleCode(any()))
          .thenThrow(Exception('disk full'));
      final controller = SettingsController(repository);

      await controller.setLocaleOverride(const Locale('en'));

      expect(controller.localeOverride, const Locale('en'));
    });
  });
}
```

Note: `writeLocaleCode(any())` needs a null-safe `any()` — `String?` is nullable, so plain `any()` works without `registerFallbackValue`.

- [ ] **Step 3: Run tests to verify they fail**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/settings_controller_test.dart`
Expected: FAIL — compile errors, `settings_repository.dart` and `settings_controller.dart` don't exist.

- [ ] **Step 4: Write the implementation**

Create `lib/repository/settings_repository.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// Persists user settings. One key per setting; absence means "default".
class SettingsRepository {
  static const _localeKey = 'locale_override';

  final SharedPreferences _prefs;

  SettingsRepository(this._prefs);

  /// The persisted language-code override, or null to follow the system.
  String? readLocaleCode() => _prefs.getString(_localeKey);

  Future<void> writeLocaleCode(String? code) async {
    if (code == null) {
      await _prefs.remove(_localeKey);
    } else {
      await _prefs.setString(_localeKey, code);
    }
  }
}
```

Create `lib/settings_controller.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/repository/settings_repository.dart';

/// App-level user settings. Null [localeOverride] means "follow the system".
class SettingsController extends ChangeNotifier {
  final SettingsRepository repository;

  Locale? _localeOverride;

  SettingsController(this.repository);

  Locale? get localeOverride => _localeOverride;

  /// Restores the persisted override. A code we no longer support (or
  /// corrupt data) degrades to following the system rather than crashing.
  void load() {
    final code = repository.readLocaleCode();
    if (code == null) return;
    final supported = AppLocalizations.supportedLocales
        .any((locale) => locale.languageCode == code);
    _localeOverride = supported ? Locale(code) : null;
  }

  Future<void> setLocaleOverride(Locale? locale) async {
    _localeOverride = locale;
    notifyListeners();
    try {
      await repository.writeLocaleCode(locale?.languageCode);
    } catch (_) {
      // The choice still applies this session; it just won't survive a
      // restart.
    }
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/settings_controller_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 6: Analyze and commit**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter analyze`
Expected: No issues found.

```bash
git add pubspec.yaml pubspec.lock lib/repository/settings_repository.dart lib/settings_controller.dart test/settings_controller_test.dart
git commit -m "feat: settings controller with persisted locale override"
```

---

### Task 2: l10n keys + SettingsScreen

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_da.arb` (+ regenerated `lib/l10n/app_localizations*.dart`)
- Create: `lib/screens/settings_screen.dart`
- Test: `test/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes: `SettingsController` from Task 1 (`localeOverride`, `setLocaleOverride`), `SettingsRepository`.
- Produces: `SettingsScreen({required SettingsController controller})` — a routable widget. Radio tile keys: `Key('language_system')`, `Key('language_en')`, `Key('language_da')`. L10n getters: `screenSettings`, `settingsLanguage`, `settingsSystemDefault`, `languageEnglish`, `languageDanish`, `navMenu`.

- [ ] **Step 1: Add l10n keys**

In `lib/l10n/app_en.arb`, after the `"screenWalkDetail"` line, add:

```json
  "screenSettings": "Settings",
  "settingsLanguage": "Language",
  "settingsSystemDefault": "System default",
  "languageEnglish": "English",
  "languageDanish": "Dansk",
  "navMenu": "Menu",
```

In `lib/l10n/app_da.arb`, after the `"screenWalkDetail"` line, add:

```json
  "screenSettings": "Indstillinger",
  "settingsLanguage": "Sprog",
  "settingsSystemDefault": "Systemstandard",
  "languageEnglish": "English",
  "languageDanish": "Dansk",
  "navMenu": "Menu",
```

(`languageEnglish`/`languageDanish` are endonyms — deliberately identical in both files. `navMenu` is used by Task 3's menu chip; added here so the l10n change lands in one commit.)

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter gen-l10n`
Expected: exits 0; `lib/l10n/app_localizations*.dart` now contain the new getters.

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/l10n_parity_test.dart`
Expected: PASS (parity holds).

- [ ] **Step 2: Write the failing widget tests**

Create `test/screens/settings_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/screens/settings_screen.dart';
import 'package:walkable/settings_controller.dart';

void main() {
  late SettingsController controller;

  Future<void> setUpController(Map<String, Object> initialPrefs) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final prefs = await SharedPreferences.getInstance();
    controller = SettingsController(SettingsRepository(prefs))..load();
  }

  Widget buildSubject({Locale locale = const Locale('en')}) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(controller: controller),
      );

  testWidgets('shows language section with the three options', (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Dansk'), findsOneWidget);
  });

  // Selection state lives on the RadioGroup ancestor (per-tile groupValue —
  // and the `checked` getter built on it — is deprecated in Flutter 3.44 and
  // unset here, so don't assert on tile.checked).
  testWidgets('system default is selected when there is no override',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    final group = tester
        .widget<RadioGroup<Locale?>>(find.byType(RadioGroup<Locale?>));
    expect(group.groupValue, isNull);
  });

  testWidgets('persisted override is the selected radio', (tester) async {
    await setUpController({'locale_override': 'da'});
    await tester.pumpWidget(buildSubject());

    final group = tester
        .widget<RadioGroup<Locale?>>(find.byType(RadioGroup<Locale?>));
    expect(group.groupValue, const Locale('da'));
  });

  testWidgets('tapping Dansk updates the controller and persists',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const Key('language_da')));
    await tester.pumpAndSettle();

    expect(controller.localeOverride, const Locale('da'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('locale_override'), 'da');
  });

  testWidgets('tapping System default clears the override', (tester) async {
    await setUpController({'locale_override': 'da'});
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const Key('language_system')));
    await tester.pumpAndSettle();

    expect(controller.localeOverride, isNull);
  });

  testWidgets('renders Danish strings under the Danish locale',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject(locale: const Locale('da')));

    expect(find.text('Indstillinger'), findsOneWidget);
    expect(find.text('Sprog'), findsOneWidget);
    expect(find.text('Systemstandard'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/screens/settings_screen_test.dart`
Expected: FAIL — compile error, `settings_screen.dart` doesn't exist.

- [ ] **Step 4: Write the implementation**

Create `lib/screens/settings_screen.dart`:

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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.screenSettings)),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                l10n.settingsLanguage,
                style: theme.textTheme.titleSmall!
                    .copyWith(color: theme.colorScheme.primary),
              ),
            ),
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
          ],
        ),
      ),
    );
  }
}
```

(`RadioGroup` supplies `groupValue`/`onChanged` to descendant tiles — the per-tile properties are deprecated in Flutter 3.44.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/screens/settings_screen_test.dart test/l10n_parity_test.dart`
Expected: PASS (all).

- [ ] **Step 6: Analyze and commit**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter analyze`
Expected: No issues found.

```bash
git add lib/l10n/ lib/screens/settings_screen.dart test/screens/settings_screen_test.dart
git commit -m "feat: settings screen with language selection"
```

---

### Task 3: Main-screen menu chip (History + Settings)

**Files:**
- Modify: `lib/screens/active_walk_screen.dart` (history chip block at ~lines 320–335; constructor at ~lines 16–28)
- Test: `test/screens/active_walk_screen_test.dart` (existing history tests at lines ~80 and ~225, plus new menu tests)

**Interfaces:**
- Consumes: `SettingsController` (Task 1), `SettingsScreen({required SettingsController controller})` (Task 2), `l10n.navMenu`/`l10n.screenSettings` (Task 2).
- Produces: `ActiveWalkScreen` gains a required constructor param `SettingsController settingsController`. Widget keys: `Key('menu_button')` (chip), `Key('history_button')` (menu item, key name kept from the old chip), `Key('settings_button')` (menu item). Task 4 relies on these keys and the new constructor param.

- [ ] **Step 1: Update existing tests and write new failing ones**

In `test/screens/active_walk_screen_test.dart`:

1. Add imports:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/screens/settings_screen.dart';
import 'package:walkable/settings_controller.dart';
```

2. Add to the `late` declarations and `setUp` body:

```dart
  late SettingsController settingsController;
```

```dart
    SharedPreferences.setMockInitialValues({});
    // SharedPreferences.getInstance() resolves synchronously enough for
    // setUp; fetch it inside buildSubject instead to keep setUp sync — see
    // the updated buildSubject below.
```

3. Replace `buildSubject` with an async variant that owns the controller:

```dart
  Future<Widget> buildSubject({Locale? locale}) async {
    final prefs = await SharedPreferences.getInstance();
    settingsController = SettingsController(SettingsRepository(prefs))..load();
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ActiveWalkScreen(
        recorder: recorder,
        repository: repository,
        settingsController: settingsController,
      ),
    );
  }
```

Update every existing `tester.pumpWidget(buildSubject(...))` call site to `tester.pumpWidget(await buildSubject(...))`.

4. Replace the test `'History button visible in idle state'` (line ~80):

```dart
  testWidgets('menu chip visible in idle state', (tester) async {
    await tester.pumpWidget(await buildSubject());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('menu_button')), findsOneWidget);
  });
```

5. Replace the test `'history button remains visible during recording'` (line ~225): same change — expect `Key('menu_button')` instead of `Key('history_button')`, rename to `'menu chip remains visible during recording'`.

6. Add new menu tests (top-level, after the idle-state group):

```dart
  testWidgets('menu opens with History and Settings items', (tester) async {
    await tester.pumpWidget(await buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('menu_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history_button')), findsOneWidget);
    expect(find.byKey(const Key('settings_button')), findsOneWidget);
  });

  testWidgets('menu History item opens the history screen', (tester) async {
    when(() => repository.findAll()).thenAnswer((_) async => []);
    await tester.pumpWidget(await buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history_button')));
    await tester.pumpAndSettle();

    expect(find.text('Walk History'), findsOneWidget);
  });

  testWidgets('menu Settings item opens the settings screen', (tester) async {
    await tester.pumpWidget(await buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
  });
```

(`findAll()` is `WalkRepository`'s list method — `lib/repository/walk_repository.dart:219` — and the stub matches `walk_history_screen_test.dart`.)

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/screens/active_walk_screen_test.dart`
Expected: FAIL — compile error (`settingsController` param doesn't exist on `ActiveWalkScreen`).

- [ ] **Step 3: Implement the menu chip**

In `lib/screens/active_walk_screen.dart`:

1. Add imports:

```dart
import 'package:walkable/screens/settings_screen.dart';
import 'package:walkable/settings_controller.dart';
```

2. Extend the widget's constructor:

```dart
class ActiveWalkScreen extends StatefulWidget {
  final WalkRecorder recorder;
  final WalkRepository repository;
  final SettingsController settingsController;

  const ActiveWalkScreen({
    super.key,
    required this.recorder,
    required this.repository,
    required this.settingsController,
  });
```

3. Replace the history-pill `Positioned` block (currently lines 320–335) with:

```dart
          // Menu pill — top left. History and Settings live in here so the
          // map stays as empty as possible.
          Positioned(
            top: topPadding,
            left: 12,
            child: MenuAnchor(
              builder: (context, menu, _) => _MapChip(
                key: const Key('menu_button'),
                onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                semanticLabel: l10n.navMenu,
                icon: const Icon(Icons.menu, size: 18),
              ),
              menuChildren: [
                MenuItemButton(
                  key: const Key('history_button'),
                  leadingIcon: const Icon(Icons.history),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          WalkHistoryScreen(repository: widget.repository),
                    ),
                  ),
                  child: Text(l10n.navHistory),
                ),
                MenuItemButton(
                  key: const Key('settings_button'),
                  leadingIcon: const Icon(Icons.settings),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        controller: widget.settingsController,
                      ),
                    ),
                  ),
                  child: Text(l10n.screenSettings),
                ),
              ],
            ),
          ),
```

4. `lib/main.dart` now fails to compile (missing param). Make the minimal wiring change so the app builds — in `main()`:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/settings_controller.dart';
```

```dart
  final prefs = await SharedPreferences.getInstance();
  final settingsController = SettingsController(SettingsRepository(prefs))
    ..load();
  runApp(WalkableApp(
    recorder: recorder,
    repository: repository,
    settingsController: settingsController,
  ));
```

And in `WalkableApp` add the field/param and pass it through to `ActiveWalkScreen`:

```dart
  final SettingsController settingsController;

  const WalkableApp({
    super.key,
    required this.recorder,
    required this.repository,
    required this.settingsController,
  });
```

```dart
      home: ActiveWalkScreen(
        recorder: recorder,
        repository: repository,
        settingsController: settingsController,
      ),
```

(The locale rebuild wiring — `ListenableBuilder` + `locale:` — is Task 4; don't add it yet. `test/widget_test.dart` also breaks here; it's rewritten in Task 4, so run only the screen tests for now.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/screens/active_walk_screen_test.dart test/screens/settings_screen_test.dart`
Expected: PASS (all).

- [ ] **Step 5: Fix widget_test.dart compile break, analyze, commit**

`test/widget_test.dart` must at least compile. Update its pump to:

```dart
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
```

with imports:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/settings_controller.dart';
```

and replace the History-text expectation (the old chip label is now inside the closed menu) with:

```dart
    // Menu chip is the single top-left entry point
    expect(find.byKey(const Key('menu_button')), findsOneWidget);
```

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test`
Expected: PASS (full suite).

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter analyze`
Expected: No issues found.

```bash
git add lib/screens/active_walk_screen.dart lib/main.dart test/screens/active_walk_screen_test.dart test/widget_test.dart
git commit -m "feat: replace history chip with menu chip holding History and Settings"
```

---

### Task 4: Locale wiring — app rebuilds and persists language choice

**Files:**
- Modify: `lib/main.dart` (build method of `WalkableApp`)
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: `SettingsController.localeOverride` (Task 1), widget keys `menu_button`/`settings_button` (Task 3), radio key `language_da` (Task 2).
- Produces: `MaterialApp` whose `locale` follows `settingsController.localeOverride` live. No new symbols.

- [ ] **Step 1: Write the failing tests**

First refactor `test/widget_test.dart` so all tests share the mock setup: move the mock creation and stubs from the existing test into `late` fields + `setUp`/`tearDown` at the top of `main()`, and delete those lines from the existing test body:

```dart
void main() {
  late MockWalkRecorder recorder;
  late MockLocationService locationService;
  late MockWalkRepository repository;
  late StreamController<WalkSnapshot> ctrl;

  setUp(() {
    recorder = MockWalkRecorder();
    locationService = MockLocationService();
    repository = MockWalkRepository();
    ctrl = StreamController<WalkSnapshot>.broadcast();

    when(() => recorder.state).thenReturn(RecorderState.idle);
    when(() => recorder.snapshots).thenAnswer((_) => ctrl.stream);
    when(() => recorder.locationService).thenReturn(locationService);
    when(() => locationService.checkAndRequestPermission())
        .thenAnswer((_) async => true);
    when(() => locationService.watchPosition())
        .thenAnswer((_) => const Stream.empty());
  });

  tearDown(() => ctrl.close());

  // ...tests...
}
```

Then append the two new tests inside `main()`:

```dart
  testWidgets('selecting Dansk switches the app language immediately',
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
    await tester.tap(find.byKey(const Key('language_da')));
    await tester.pumpAndSettle();

    // The settings screen re-renders in Danish without restart
    expect(find.text('Indstillinger'), findsOneWidget);
    expect(find.text('Sprog'), findsOneWidget);
    // And the choice is persisted
    expect(prefs.getString('locale_override'), 'da');
  });

  testWidgets('starts in Danish when a Danish override was persisted',
      (tester) async {
    SharedPreferences.setMockInitialValues({'locale_override': 'da'});
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

    // History menu item renders in Danish
    expect(find.text('Tidligere gåture'), findsOneWidget);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test test/widget_test.dart`
Expected: the two new tests FAIL — `MaterialApp.locale` isn't wired, so the UI stays in the test-environment default (English). (`find.text('Indstillinger')` / `find.text('Tidligere gåture')` find nothing.)

- [ ] **Step 3: Wire the locale into MaterialApp**

In `lib/main.dart`, wrap the `MaterialApp` in `WalkableApp.build` with a `ListenableBuilder` and set `locale:`:

```dart
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settingsController,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        // Null (no override) falls through to the device locale via the
        // resolution callback below.
        locale: settingsController.localeOverride,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Match the device language; fall back to English for anything we
        // don't translate (rather than the first supported locale, which is
        // Danish).
        localeResolutionCallback: (deviceLocale, supportedLocales) {
          for (final locale in supportedLocales) {
            if (locale.languageCode == deviceLocale?.languageCode) {
              return locale;
            }
          }
          return const Locale('en');
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/walk-detail') {
            final walk = settings.arguments as Walk;
            return MaterialPageRoute(
              builder: (_) => WalkDetailScreen(walk: walk),
            );
          }
          return null;
        },
        home: ActiveWalkScreen(
          recorder: recorder,
          repository: repository,
          settingsController: settingsController,
        ),
      ),
    );
  }
```

- [ ] **Step 4: Run the full suite to verify everything passes**

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter test`
Expected: PASS (full suite).

Run: `/home/alexander/fvm/versions/3.44.0/bin/flutter analyze`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart test/widget_test.dart
git commit -m "feat: apply persisted language override to the app locale"
```

---

## Done criteria

- Full test suite and `flutter analyze` pass.
- Manual smoke (optional, device/emulator): menu chip → Settings → pick Dansk → UI flips to Danish instantly; kill + relaunch → still Danish; pick System default → follows device language.
- Push branch and open a PR against `main` per the usual workflow.
