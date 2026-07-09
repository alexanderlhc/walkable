# Play resubmission — Prominent Disclosure (v0.3.1, build 13)

Rejection: **Inadequate Prominent Disclosure** (User Data policy), issue
`IN_APP_EXPERIENCE-749` — the initial runtime location permission request was
not immediately preceded by an in-app disclosure.

## Note for the Play review team (paste into the review/appeal notes field)

> Thank you for the review. We have fixed the flagged issue in version 0.3.1
> (versionCode 13).
>
> Previously, the initial "while in use" location permission dialog was
> requested on app launch without a preceding in-app disclosure (as shown in
> the attached screenshot IN_APP_EXPERIENCE-749); only the background
> ("Allow all the time") request showed one.
>
> In this build, **every** runtime location permission request is immediately
> preceded by a prominent in-app disclosure that the user must affirmatively
> accept:
>
> 1. On first launch, before the initial location permission dialog, the app
>    shows a "Location access" disclosure explaining that Walkable collects
>    location data to show the user's position on the map and record their
>    walking route while using the app, and that the data never leaves the
>    device. The OS permission dialog is only requested after the user taps
>    "Continue". If the user declines, no system dialog is shown.
> 2. When starting a walk, before the "Allow all the time" background location
>    dialog, the app shows the background-location disclosure (unchanged from
>    the previous submission). The OS dialog is only requested after the user
>    accepts.
>
> The disclosures are implemented as blocking in-app dialogs shown immediately
> before their respective system prompts, and declining a disclosure always
> skips the corresponding system prompt entirely.
>
> Screenshots of both disclosures are attached
> (foreground_disclosure_en.png, disclosure_en.png).

## Evidence

- `docs/screenshots/disclosure/foreground_disclosure_en.png` — disclosure shown
  on screen open, immediately before the initial OS location prompt (the
  prompt the rejection flagged).
- `docs/screenshots/disclosure/disclosure_en.png` — disclosure shown on Start,
  immediately before the OS "Allow all the time" prompt.

Regenerate both with:

```sh
SCREENSHOT_OUT=docs/screenshots/disclosure \
fvm flutter drive --profile \
  --driver=test_driver/screenshot_driver.dart \
  --target=integration_test/disclosure_screenshot_test.dart \
  -d <emulator-id>
```

## What changed in the code

Commit `44c2e7d`. The disclosure is now structural: `LocationService` can only
surface an OS location prompt through an accepted consent gate
(`LocationConsent`), one per prompt (foreground and background), threaded
through `WalkRecorder.start()`/`resume()` and shown by `ActiveWalkScreen`.
A regression test (`test/location/foreground_disclosure_regression_test.dart`)
fails on the rejected behaviour and pins the guarantee.
