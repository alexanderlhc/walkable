# Theme setting (Light / Dark / System default) — design

Date: 2026-07-06
Status: approved pending user review

## Goal

Add a second setting to the settings page: a theme override (Light / Dark /
System default), following the language-override pattern.

## Decisions (made with user)

- Extend the existing `SettingsController`/`SettingsRepository` — no
  separate theme controller.
- The repository API speaks `ThemeMode` (Flutter's enum) in both
  directions; the persisted string encoding is a private detail of the
  repository. (User feedback: no `String?` in the theme API.)
- UI labels: "System default" (not "Auto"), consistent with the language
  section.
- Implementation style: TDD, red-green-refactor.
- Branch: `feature/settings-theme` off `feature/settings-language`
  (builds directly on that code; PR after #23 merges).

## 1. Data layer

`SettingsRepository` gains:

- `ThemeMode readThemeMode()` — reads prefs key `theme_mode`; absent,
  unknown value, or a read that throws (type-corrupt data) all return
  `ThemeMode.system`.
- `Future<void> writeThemeMode(ThemeMode mode)` — `ThemeMode.system`
  removes the key; `light`/`dark` store `mode.name`.

`SettingsController` gains:

- `ThemeMode get themeMode` (initial value `ThemeMode.system`)
- `load()` additionally restores the theme via `readThemeMode()`.
- `Future<void> setThemeMode(ThemeMode mode)` — updates, notifies, then
  persists best-effort (write failure keeps the in-memory value for the
  session; same semantics as the locale setter).

## 2. Wiring

`lib/main.dart`: the `MaterialApp` already rebuilds via
`ListenableBuilder`; change `themeMode: ThemeMode.system` to
`themeMode: settingsController.themeMode`. Nothing else changes — map
tiles already follow `Theme.of(context).brightness` and switch
automatically.

## 3. UI

`SettingsScreen` gets a second section below Language, same shape as the
language section: "Theme" header + `RadioGroup<ThemeMode>` with three
`RadioListTile<ThemeMode>`s:

- **System default** → `ThemeMode.system` (key `theme_system`)
- **Light** → `ThemeMode.light` (key `theme_light`)
- **Dark** → `ThemeMode.dark` (key `theme_dark`)

Selection applies instantly (no save button).

New l10n keys in both arb files: `settingsTheme` ("Theme"/"Tema"),
`themeLight` ("Light"/"Lyst"), `themeDark` ("Dark"/"Mørkt"). The existing
`settingsSystemDefault` is reused for the system option.

## 4. Testing (TDD — tests written first per unit)

- **Unit** (`test/settings_controller_test.dart`): default when nothing
  stored; persisted `dark` restored; unknown stored value → system; read
  throw → system; `setThemeMode` updates + notifies + persists;
  write-failure keeps in-memory value.
- **Widget** (`test/screens/settings_screen_test.dart`): three theme
  radios render with system selected by default; tapping Dark updates
  controller + prefs; Danish strings under `da` locale.
- **App-level** (`test/widget_test.dart`): picking Dark flips
  `MaterialApp.themeMode` live; persisted `dark` starts dark.
- L10n parity test covers the new keys automatically.

## Out of scope

- Any further settings; custom accent colors; per-screen theming.
