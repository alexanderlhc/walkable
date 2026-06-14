# App icon

Bright, flat icon for Walkable: a green walking figure on a light green gradient.

The figure is Google's Material Symbols `directions_walk` glyph (Apache-2.0),
recoloured with a green gradient — using a professionally-drawn glyph instead of
hand-authored paths.

## Sources
- `icon_master.svg` — full square icon (background + figure). Used for the
  legacy launcher icon and the Play Store listing image.
- `icon_background.svg` — adaptive-icon background layer (light green gradient).
- `walker.svg` — the walking-figure artwork, used for the adaptive foreground.
- `play_store_icon_512.png` — 512×512 icon for the Play Store listing.
- `feature_graphic.svg` / `feature_graphic.png` — 1024×500 Play Store feature graphic.

## Regenerate
```sh
bash docs/icon/generate.sh
```
This rewrites the legacy `ic_launcher.png` and the adaptive `ic_launcher_foreground.png`
/ `ic_launcher_background.png` layers under `android/app/src/main/res/mipmap-*`.
The adaptive descriptor lives at `mipmap-anydpi-v26/ic_launcher.xml`.

Requires `rsvg-convert` and ImageMagick. Rebuild the app to see the new icon.
