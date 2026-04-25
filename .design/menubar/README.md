# Rotor Menu Bar Icon — Arcs

## SVG sources

- `template/rotor-menubar.svg` — black strokes. Use as a **template image** (`NSImage.isTemplate = true` / `Image().renderingMode(.template)`). macOS auto-inverts for dark mode.
- `light/rotor-menubar.svg` — explicit dark-ink version (#1A1A1A).
- `dark/rotor-menubar.svg` — explicit white version for dark backgrounds.

## PNG rasters

Each variant folder ships three sizes:
- `rotor-menubar-18.png` — @1x
- `rotor-menubar-36-2x.png` — @2x Retina
- `rotor-menubar-54-3x.png` — @3x

## .iconset

`rotor.iconset/` contains 16/32/64 at 1x + 2x (rename `_2x` → `@2x` before running `iconutil`).

## Swift / SwiftUI usage

```swift
// AppKit
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
if let img = NSImage(named: "rotor-menubar") {
  img.isTemplate = true
  item.button?.image = img
}

// SwiftUI (macOS 13+)
Image("rotor-menubar")
  .renderingMode(.template)
```

Using the template SVG is the recommended path — dark mode is free.
