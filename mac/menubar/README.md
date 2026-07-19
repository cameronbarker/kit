# Kit Menu Bar Scaffold

This directory is a foundation for a future native macOS menu bar helper. It is intentionally thin: the menu bar process should present Kit state and trigger Kit actions, while core behavior stays in reusable Ruby commands and services.

## Boundary

The menu bar helper must call stable Kit commands and consume JSON. It should not scrape human-readable CLI output.

Current bridge entry point:

```bash
kit status --json
```

Planned JSON entry points for future work:

```bash
kit surface --json
kit followup --overdue --json
kit prepare --next --json
kit brief --json
kit listen status --json
```

The Ruby bridge lives under `lib/kit/app_bridge/`. It exposes machine-readable status for app surfaces without depending on AppKit, notifications, or any future GUI process.

## Swift Scaffold

`Package.swift` defines an Xcode-project-free Swift package with a minimal AppKit status item implementation in `Sources/KitMenuBar/KitMenuBar.swift`.

Build:

```bash
swift build
```

Run against an installed `kit`:

```bash
swift run KitMenuBar
```

Run against this checkout:

```bash
KIT_CLI="$PWD/../../bin/kit" swift run KitMenuBar
```

The scaffold currently reads `kit status --json`, shows a small health indicator, and renders planned menu actions as disabled items. It does not implement production packaging, login items, app signing, global shortcuts, quick capture UI, or real action execution yet.

## Future Direction

Add Ruby JSON contracts before wiring new menu bar actions. For example, implement `kit surface --json` in Ruby first, test that output, then update the Swift helper to decode and display it.

Keep macOS-specific concerns here:

- `NSStatusItem` menu rendering
- app lifecycle and packaging
- opening URLs such as Obsidian links
- user-facing quick capture windows

Keep Kit behavior in Ruby:

- open loop and commitment queries
- meeting prep selection
- brief generation
- listen pipeline control
- notification policy and status
