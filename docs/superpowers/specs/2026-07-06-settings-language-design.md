# Settings page with language selection — design

Date: 2026-07-06
Status: approved pending user review

## Goal

Add a settings page (first setting: language) following the app's Material 3
design system while making the main screen *less* cluttered, not more.

## Decisions (made with user)

- Locale model: **system default + explicit override**. App follows the
  device language unless the user picks one; "System default" is an option.
- Entry point: **merge main-screen chips into a menu**. The labeled
  "Walk History" chip is replaced by an icon-only menu chip; History and
  Settings live in the menu.
- Picker UI: **inline radio list** on the settings page (no dialog,
  no save button — selection applies instantly).
- Architecture: **SettingsController (ChangeNotifier) + SettingsRepository
  on shared_preferences**, constructor-injected from `main()` like the
  existing `WalkRecorder`/`WalkRepository`.
- Implementation style: **TDD, red-green-refactor** (write failing test,
  make it pass, refactor) for every unit below.

## 1. Entry point (main screen)

Replace the top-left "Walk History" `_MapChip` in
`lib/screens/active_walk_screen.dart` with an icon-only chip in the same
visual style (icon: `Icons.menu`), opening a Material 3 `MenuAnchor` with
two items:

- **History** (`Icons.history`) → pushes `WalkHistoryScreen` (unchanged behavior)
- **Settings** (`Icons.settings`) → pushes `SettingsScreen`

Recenter chip and bottom panel are untouched.

## 2. Settings screen

New `lib/screens/settings_screen.dart`:

- `Scaffold` + `AppBar` titled "Settings".
- Body: `ListView` with a "Language" section header and three
  `RadioListTile<Locale?>` entries:
  - **System default** → `null`
  - **English** → `Locale('en')`
  - **Dansk** → `Locale('da')`
- Language names are endonyms (identical string in both `.arb` files).
- New l10n keys in `app_en.arb` + `app_da.arb`: settings title, language
  section header, system default label, and the two endonym labels.
  The existing `l10n_parity_test.dart` covers key parity automatically.

## 3. State & persistence

- New dependency: `shared_preferences`.
- `SettingsRepository`: reads/writes a language-code string under a single
  key; key absent = system default.
- `SettingsController extends ChangeNotifier`:
  - `Locale? localeOverride` (null = follow system)
  - `Future<void> load()` — reads persisted value at startup
  - `Future<void> setLocaleOverride(Locale?)` — persists and notifies
- Error handling:
  - Unknown/corrupt stored language code (e.g. `"de"`, garbage) → treated
    as system default.
  - Persistence write failure → in-memory value still applies for the
    session; setting silently doesn't survive restart.

## 4. Wiring (`lib/main.dart`)

- `main()` creates `SettingsRepository` + `SettingsController` and awaits
  `controller.load()` before `runApp` (prefs read is fast; avoids locale
  flicker).
- `ListenableBuilder` (listening to the controller) wraps `MaterialApp`;
  `locale: controller.localeOverride`. A null locale falls through to the
  existing `localeResolutionCallback`, so system behavior is unchanged.
- Controller is passed to screens by constructor, matching existing DI style.
- `SettingsScreen` is pushed with `MaterialPageRoute` from the menu.

## 5. Testing (TDD — tests written first per unit)

- **Unit** (`test/settings_controller_test.dart`): load with no stored
  value / stored `da` / corrupt value; setLocaleOverride persists and
  notifies; write-failure keeps in-memory value. Use
  `SharedPreferences.setMockInitialValues` and mocktail where needed.
- **Widget** (`test/screens/settings_screen_test.dart`): radios reflect
  controller state; tapping a radio updates controller; strings localized
  in both locales.
- **Widget** (`test/screens/active_walk_screen_test.dart`): menu chip
  opens menu; History and Settings items navigate correctly.
- **App-level** (`test/widget_test.dart`): selecting Dansk rebuilds the
  app in Danish; restart with persisted value starts in Danish.

## Out of scope

- Any settings beyond language (theme, units, etc.) — the page structure
  accommodates them later.
- Migrating existing screens to the controller for anything but locale.
