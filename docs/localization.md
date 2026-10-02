# Localization

Compositor ships English as its source language and Simplified Chinese (`zh-Hans`) as a
translation. The interface follows the Mac's language: a Chinese Mac shows Chinese, an English Mac
shows English, and System Settings › General › Language & Region › Applications can override the
choice for Compositor alone.

## Where the strings live

Every translatable string is an English literal in the Swift source, and its translation lives in
[`Compositor/Localizable.xcstrings`](../Compositor/Localizable.xcstrings), the project's string
catalog. The catalog is a normal resource: the app target picks it up from the `Compositor` folder,
and Xcode compiles it into `zh-Hans.lproj/Localizable.strings` inside the built app.

English needs no catalog entries — the key *is* the English text, so a missing translation falls
back to English rather than to an empty label.

## How a string becomes translatable

Xcode extracts strings from the source during a build (`SWIFT_EMIT_LOC_STRINGS = YES`, already set
for the app target). What is extracted:

| Written as | Extracted |
| --- | --- |
| `Text("Drop Shadow")`, `Button("Apply")`, `Label("Opacity", …)`, `Toggle("Visible", …)` | yes |
| `.help("Paint with the foreground color")`, `.accessibilityLabel("Add Mask")` | yes |
| `String(localized: "Merge Down")` | yes |
| `String(localized: "Hide \(name)")` → key `Hide %@` | yes, with the placeholder |
| a parameter typed `LocalizedStringKey` called with a literal | yes |
| `Text(someStringVariable)` | **no** — it renders verbatim |
| `NSLocalizedString(…)`, `String(localized: someVariable)` | **no** |

So when a label travels through a `String` (an AppKit call, a model enum, a value passed into a
view), localize it where the literal is written:

```swift
// A model label: localize the property, and every call site is fixed at once.
var displayName: String {
    switch self {
    case .multiply: String(localized: "Multiply")
    case .screen:   String(localized: "Screen")
    }
}

// An AppKit call.
item.title = String(localized: "Duplicate Layer")
```

Never localize: SF Symbol names, Core Image filter names, UTType identifiers, file extensions,
`FloatingPanelController`/`@AppStorage` keys, JSON and project-format keys, PSD channel
identifiers, and anything the user typed or that came from a file (layer names, project names,
font names). Never change an enum's `rawValue` to localize it — raw values are persisted in the
project format; add a `displayName` property instead.

A value that is both shown *and* compared, or written to disk, needs two: keep the English value
for the comparison or the file, and add a localized accessor for the interface. Keyboard shortcuts
go further — `ShortcutDefinition.id` is the key a saved override is stored under, so it is built
from the group and the shortcut's shipped chord rather than from either localized label, and the
shortcut sheet matches definitions by that identity.

### One English word, two meanings

Two screens can share an English word that has to read differently in another language: `Light` is
Camera Raw's *Light* panel (光线) and also the dither filter's pale swatch (浅色). The catalog holds
one translation per key, so give one of the sites its own key while keeping the English text it
shows:

```swift
// Shows "Light" in English, and keeps its own catalog entry for the translation.
case .light: String(localized: "Light panel", defaultValue: "Light")
```

The same shape names the Levels eyedropper's tonal points, which Chinese Photoshop calls 黑场 / 灰场 /
白场 while the fill colors of the same words stay 黑色 / 灰色 / 白色:

```swift
case .black: String(localized: "Black point", defaultValue: "Black")
```

### Names the app generates

New layers, folders and shapes are named in the interface language — 图层 1, 图层组 2, 矩形 1 — and
that name is what the project file stores, exactly as Photoshop's Chinese build does. The numbering
scan therefore builds its needle with the same `String(localized:)` expression it stores, so it
still skips names already in the document. This is deliberate: do not "fix" it by pinning the
generated name to English, and do not compare a generated name against a hard-coded English string.

## Refreshing the catalog

After adding or changing interface text, rebuild and merge the extracted strings into the catalog:

```sh
xcodebuild -project Compositor.xcodeproj -scheme Compositor -destination 'platform=macOS' \
  -derivedDataPath /tmp/compositor-build CODE_SIGNING_ALLOWED=NO build

xcrun xcstringstool sync Compositor/Localizable.xcstrings \
  --stringsdata /tmp/compositor-build/Build/Intermediates.noindex/Compositor.build/Debug/Compositor.build/Objects-normal/arm64/*.stringsdata
```

`xcstringstool sync` adds new keys, and marks keys that no longer appear in the source as stale so
they can be removed. Xcode's catalog editor does the same thing through the build, and its
**Editor › Export/Import Localizations** commands round-trip the catalog through XLIFF if you would
rather translate outside Xcode.

## Adding another language

1. Add the language to the project's known regions (the target's `knownRegions` in
   `project.pbxproj`, or Xcode's project editor › Info › Localizations).
2. Open `Compositor/Localizable.xcstrings` in Xcode, add the language, and translate the entries.
3. Build and check `Compositor.app/Contents/Resources/<language>.lproj/Localizable.strings`.

## Tests run in English

`CompositorTests` asserts the app's own English text (undo names, import conversion messages,
accessibility labels), so the shared scheme's test action pins the language to English and the
region to the United States. That keeps the suite meaningful on a Mac whose language is Chinese.
The pinning lives in `Compositor.xcodeproj/xcshareddata/xcschemes/Compositor.xcscheme`; remove it
only if the tests stop depending on English strings.
