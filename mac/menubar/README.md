# Kit Menu Bar

This directory contains a thin native macOS menu bar helper. The menu bar process presents Kit state and triggers Kit actions, while core behavior stays in reusable Ruby commands and services.

## Boundary

The menu bar helper must call stable Kit commands and consume JSON. It should not scrape human-readable CLI output.

Current bridge entry points:

```bash
kit status --json
kit listen status --json
kit listen start Base --json "Menubar Listen"
kit listen pause --json
kit listen resume --json
kit listen stop --json
kit listen transcribe --json INPUT
kit surface --json
kit surface --needs-review-only --json
kit followup --waiting-on-me --json
kit brief --json
```

Planned JSON entry points for future work:

```bash
kit prepare --next --json
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

Or start it from the Kit CLI at the repo root:

```bash
bin/kit menubar
bin/kit menubar --foreground
bin/kit menubar stop
bin/kit menubar restart
```

The helper reads `kit status --json`, `kit listen status --json`, `kit surface --json`, and `kit followup --waiting-on-me --json`. The primary menu is ADHD-focused instead of a command dump:

- Now: `Needs review (N)` runs `kit surface --needs-review-only --json`; `Waiting on me (N)` runs `kit followup --waiting-on-me --json`; a short disabled `Next:` line may show the top attention item.
- Capture: listen start/pause/resume/stop controls stay near the top, with live elapsed time, chunks, device, transcription progress, and the existing status item states (`● REC`, `⏸`, `…`). `Transcribe Audio File…` opens a native single-file picker for existing audio/video and runs `kit listen transcribe --json INPUT` asynchronously when listen is idle.
- Support: `Today's Surface` runs `kit surface`; `Weekly Brief` runs `kit brief --json`.
- Footer: `Refresh` rebuilds counts and listen state; `Quit` exits the helper.

Menu opening renders from cached status, listen, and attention snapshots so the menu is not blocked by Ruby process startup. Attention counts may be stale for up to 15 seconds during normal opens; `Refresh` forces a new attention refresh asynchronously.

Implemented actions run asynchronously and send a small Kit notification with the result summary, then refresh counts. Planned or unimplemented commands are not shown in the primary menu. Notification plumbing and last-error details are kept behind a Diagnostics submenu when there is something to diagnose.

Idle healthy status uses the Kit icon. Recording, paused, transcribing, and error states keep the existing visible title behavior. When idle attention is needed, the icon remains and the tooltip includes counts such as `Needs review: 3`.

It does not implement production packaging, login items, app signing, global shortcuts, floating panels, or quick capture UI yet.

## Future Direction

Add Ruby JSON contracts before wiring new menu bar actions. Keep the Swift helper thin: it presents counts and triggers stable Kit commands, while Ruby remains the source of truth.

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
