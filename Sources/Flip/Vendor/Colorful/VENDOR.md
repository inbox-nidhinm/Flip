# Colorful — vendored

Source: https://github.com/jaywcjlove/Colorful @ v1.0.0 · MIT (see `LICENSE`).

Copied in rather than taken as a SwiftPM dependency, for three reasons: it does
not build unpatched (below), Flip otherwise has no dependencies and `make-app.sh`
builds offline, and this is six small files under a permissive licence.

## Local changes

- **`Colors.swift` — `import SwiftUICore` → `import SwiftUI`.** Not cosmetic:
  the package does not compile without it on Swift 6.2 / the Xcode 26 SDK, which
  rejects the import as *"module 'SwiftUICore' is an implementation detail of
  'SwiftUI'"*. Present in both `v1.0.0` and `main`.
- **Thumb size 28 → 14** (`AlphaSliderModel.pointSize`). Halves the indicator,
  and with it the hue and alpha bars, whose heights are tied to it.
- **Thumb rings 4/2 → 2/1.** At a 14pt thumb the original rings left no fill
  visible — the indicator became a white ring with no colour in it.
- **`cornerRadius` on `Saturation`, `HueSlider` and `AlphaSlider`.** Upstream
  hard-codes the corners for its own stacked layout: the box is rounded on top
  and square below, the bars are square everywhere. Flip stands them apart with
  gaps, so each needs its own rounding.
- **Fixed an upstream bug:** all three views passed `bottomTrailingRadius` for
  `bottomLeadingRadius`, so that corner could never be set.
- **Removed `Colorful.swift` and `ColorfulPicker.swift`.** Flip composes the
  three sub-views itself. `ColorfulPicker` also draws its own system-styled well,
  and both route configuration through `showsAlpha(_:)`, which mutates an
  `@ObservedObject` from inside `body`.
- **Indicators clamped inside their frames.** Upstream centres each on its true
  position, so at any edge half falls outside — overlapping the next thing in
  the stack, or leaving a half-circle when clipped. Costs up to 7pt of accuracy
  when a value is hard against its limit.
- **`trackHeight` on `HueSlider` and `AlphaSlider`.** Upstream ties the bar's
  height to the indicator's, so the bar is always exactly as tall as the circle
  riding it. Flip draws a thin bar with the indicator standing proud of it.
