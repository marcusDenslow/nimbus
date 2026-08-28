# Nimbus

A controller-first, big-box-art shelf for your GeForce NOW library on macOS. Think Steam Big Picture, if it dressed like a native Mac app.

Nimbus is a *launcher*, not a streaming client: pressing Play deep-links into the official GeForce NOW app (`geforcenow://route/#?cmsId=…`), which handles the actual session. The GFN app must stay installed.

## Build & run

Requires only the Xcode Command Line Tools (no Xcode):

```sh
./build.sh
open build/Nimbus.app
```

To install, copy `build/Nimbus.app` to `/Applications`.

## Using it

|                | Controller | Keyboard |
|----------------|-----------|----------|
| Move focus     | D-pad / left stick | Arrow keys |
| Play           | A | Return |
| Add games      | Y or Menu | ⌘F or `/` |
| Remove         | X | Delete |
| Sync GFN library | Options/View | ⌘S |
| Close search   | B | Esc |

- **Sync**: imports your actual GeForce NOW account library. NVIDIA has no public per-account API, but the GFN client logs every library title on startup and its service-worker cache holds full game records (cmsId + artwork), so Nimbus reads those local files — no login, no network. Open the GFN app once before the first sync so the log is fresh.
- **Add games**: search covers NVIDIA's public supported-games catalog plus every game recovered from the GFN client cache (the public list is years stale; the cache supplies modern titles like Crimson Desert and CS2).
- Your library lives in `~/Library/Application Support/Nimbus/library.json`.
- Box art: Steam CDN capsule for Steam titles, NVIDIA banner from the GFN cache otherwise, colored fallback tile as last resort.
- Library sorts recently-played first, then alphabetical.

## Code layout

- `AppModel.swift` — state, navigation, persistence, catalog fetch
- `GFNSync.swift` — reads the GFN client's logs and service-worker cache for library sync and catalog supplements
- `InputRouter.swift` — 30 Hz controller polling with hold-to-repeat, plus a keyboard event monitor
- `ImageCache.swift` — memory + disk box-art cache with in-flight dedupe
- `NimbusApp.swift` / `LibraryView.swift` / `SearchOverlay.swift` / `GameCard.swift` — UI
- `ViewState.swift` — `@State` replacement; the macOS 27 SDK's `@State` macro plugin isn't shipped with the Command Line Tools
