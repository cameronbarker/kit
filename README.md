# Kit

`kit` is a personal leadership toolkit for engineering managers.

It turns conversations, notes, calendar context, and work signals into commitments, reminders, briefs, prep, and reflection. Its first job is simple: help a manager remember what they said they would do and close loops reliably.

`kit` is not an AI manager. It does not replace judgment, coaching, trust, accountability, or human decision-making.

## Current Status

This repository currently contains the first root-level `kit` CLI, the first integrated `kit listen` implementation, the first deterministic `kit notice` extractor, the first `kit remember` durable-note writer, the first `kit surface` daily attention list, a thin macOS menu bar helper, and the intended Kit Obsidian plugin surface. The rest of the command surface remains a north star for the intended workflow.

The old `Listen/` prototype remains ignored as a migration archive because it contains standalone project scaffolding, local recordings/transcripts, a nested `.git`, and generated Python environment artifacts. Useful source, tests, and Python worker files have been migrated into `lib/kit/listen/` and `test/kit/listen/`.

This repo intentionally does not track local usage data: `.env`, recordings, transcripts, extracts, packaged model files, build outputs, virtual environments, Obsidian workspace state, local vault notes, and local Obsidian playground/tooling folders are ignored.

## Usage

Run the CLI from the repository root:

```bash
bin/kit help
bin/kit version
bin/kit listen help
bin/kit listen status --json
bin/kit notice --me "Cameron" latest
bin/kit notice --json --me "Cameron" transcripts/json/platform-sync.json
bin/kit remember --vault obsidian latest
bin/kit remember --json --dry-run latest
bin/kit surface --vault obsidian
bin/kit surface --json
bin/kit status --json
bin/kit notify "Review open commitments"
bin/kit menubar
```

Install runtime dependencies on a Mac with:

```bash
./install.sh
```

The current help output describes the intended workflow:

```text
listen -> notice -> remember -> surface -> prepare/brief/followup -> reflect
```

## Commands

```text
listen      Record and transcribe conversations
notice      Extract commitments, decisions, and open loops
remember    Write notice items into durable notes
notify      Send a simple local Kit notification
status      Show machine-readable Kit app bridge status
menubar     Start the macOS Kit menu bar helper
surface     Show what needs attention now
prepare     Build context packs for meetings and 1:1s
brief       Draft leadership and stakeholder updates
followup    Track promises, waiting-on items, and stale loops
reflect     Review patterns over time
qmd         Manage/search the local qmd index
```

The `listen` command is implemented as a local recording and transcription pipeline. It can list ffmpeg audio devices, run chunked background recording sessions, pause/resume/stop an active session, track recording state, show the latest recording metadata, transcribe an existing audio/video file, and re-render transcript artifacts from raw JSON. The older foreground `record` command remains available.

The `notice` command reads normalized transcript JSON from `kit listen` and writes review-required extracts of possible commitments, decisions, and open loops. It is deterministic and offline in this first version; no LLM, network, or external Ruby gem is required. Pass `--me NAME` or set `KIT_ME` to classify first-person commitments as yours. Without an identity, `notice` still runs but marks commitment perspective for human review instead of guessing.

The `remember` command reads notice extract JSON and upserts possible commitments, decisions, and open loops into durable Markdown notes. It preserves review-required status and citations rather than promoting possible items into trusted facts. By default it writes into the ignored repo-local `obsidian/` notes area; pass `--vault DIR` or set `KIT_VAULT` to target another vault.

The `surface` command reads Kit-managed durable notes and shows the daily attention list. It uses Obsidian checkbox state as the current completion source of truth and keeps possible or unknown-perspective items in a needs-review lane instead of treating them as trusted. By default it reads from the ignored repo-local `obsidian/` notes area; pass `--vault DIR` or set `KIT_VAULT` to target another durable notes root.

The `notify` command is implemented as a small macOS notification utility backed by `terminal-notifier` and uses `assets/kit-icon.png` as its notification app icon. The `status --json` command exposes a stable app bridge contract for future non-CLI surfaces. The `menubar` command launches the thin Swift helper in `mac/menubar/` against this checkout's `bin/kit`. Other planned commands currently return an intentional "not implemented yet" message.

## App Bridge

Kit keeps Mac-facing UI thin. Future app surfaces should call stable Kit commands and consume JSON rather than scrape human-readable CLI output.

Current bridge:

```bash
bin/kit status --json
```

The Ruby bridge lives in `lib/kit/app_bridge/`. A native macOS menu bar scaffold lives in `mac/menubar/` and documents how a future helper should integrate with Kit core commands.

## Obsidian

The tracked Obsidian surface lives in `obsidian/.obsidian/plugins/kit/`. It is a local Kit plugin scaffold, not a backup of vault usage or personal notes.

The vault notes, workspace layout, plugin private data, and the local `hello-world` Obsidian API playground are ignored by git.

To develop the plugin (TypeScript → `main.js`):

```bash
cd obsidian/.obsidian/plugins/kit
npm install
npm run dev
```

Use `npm run build` for a production bundle. Reload Obsidian (or disable/enable the plugin) after rebuilds.

## Listen

`kit listen` is the migrated implementation from the former standalone Listen prototype. Ruby owns the CLI and artifact workflow; Python is only used by the local WhisperX/pyannote worker.

Default local output is ignored by git:

```text
recordings/
  <timestamp>-<slug>/
    session.yml
    chunks/chunk-000001.wav
  <timestamp>-<slug>.m4a
  <timestamp>-<slug>.yml

transcripts/
  raw/<slug>.raw.json
  json/<slug>.json
  md/<slug>.md
  maps/<slug>.speaker-map.yml

extracts/
  json/<slug>.notice.json
  md/<slug>.notice.md

model/
  config.json
  model.bin
  tokenizer.json
  vocabulary.txt
  wav2vec2_fairseq_base_ls960_asr_ls960.pth
  speaker-diarization.yml
```

Common commands:

```bash
bin/kit listen devices
bin/kit listen start "Platform Sync" --device "Loopback Audio"
bin/kit listen pause
bin/kit listen resume
bin/kit listen stop --json
bin/kit listen record "Platform Sync" --device "Loopback Audio"
bin/kit listen record "Platform Sync" --format m4a --transcribe
bin/kit listen status --json
bin/kit listen latest --json
bin/kit listen transcribe --mock path/to/meeting.m4a
bin/kit listen render path/to/meeting.m4a
```

For recording, pass `--device` or set `KIT_LISTEN_AUDIO_DEVICE`. The legacy `LEADERSHIP_TRANSCRIPTS_AUDIO_DEVICE` env var is still accepted during migration.

Mock transcription requires no Python ML install. Real local transcription requires Python 3.11 or 3.12 dependencies from `lib/kit/listen/python/requirements.txt`, ffmpeg on `PATH`, and packaged model files in ignored repo-local `model/` storage. Runtime transcription is offline-only and never downloads models.

## Notice

`kit notice` expects normalized transcript JSON as its machine input. You can pass a transcript JSON path, a slug from `transcripts/json/`, `latest`, or no input to use the newest transcript JSON.

Common commands:

```bash
bin/kit notice --me "Cameron" latest
bin/kit notice --me "Cameron" platform-sync
bin/kit notice --json --me "Cameron" transcripts/json/platform-sync.json
bin/kit notice --transcripts-dir transcripts --extracts-dir extracts platform-sync
```

Outputs are review artifacts, not trusted notes:

```text
extracts/json/<slug>.notice.json
extracts/md/<slug>.notice.md
```

Each extracted item includes source citation details back to the transcript segment, including speaker, raw speaker, timestamp, and quote. Human review remains required; `remember` preserves possible/review-required labels in durable notes.

## Remember

`kit remember` expects notice extract JSON as its machine input. You can pass an extract JSON path, a slug from `extracts/json/`, `latest`, or no input to use the newest notice extract.

Common commands:

```bash
bin/kit remember latest
bin/kit remember platform-sync
bin/kit remember --vault obsidian platform-sync
bin/kit remember --json --dry-run latest
bin/kit remember pending --vault obsidian
bin/kit remember accept --vault obsidian platform-sync-c001
bin/kit remember reject --vault obsidian platform-sync-c002
```

Default note targets:

```text
Inbox/Kit Inbox.md
Commitments/Commitments.md
Decisions/Decisions.md
Open Loops/Open Loops.md
```

Remembered items are written as Kit-managed Markdown blocks keyed by stable notice item ids, for example `<!-- kit:item platform-sync-c001 -->`. Re-running `remember` updates existing Kit-managed blocks instead of blindly duplicating them. Keep manual edits outside those managed blocks.

Remember also owns the thin trust gate for managed items. `kit remember accept ITEM_ID...` changes only the inline trust status to `accepted`; it does not check the Obsidian checkbox or change text, owner, source, citations, or metadata. `kit remember reject ITEM_ID...` changes only the inline trust status to `rejected`. `kit remember pending` lists open, untrusted, non-rejected managed items so ids can be reviewed before accepting.

## Surface

`kit surface` reads the durable notes root and produces a read-only daily attention list from Kit-managed item blocks. Vault home means the durable notes root: by default this is repo-local `obsidian/`, and it can be overridden with `--vault DIR` or `KIT_VAULT`.

Common commands:

```bash
bin/kit surface
bin/kit surface --vault obsidian
bin/kit surface --json
bin/kit surface --me "Cameron"
bin/kit surface --needs-review-only
```

Surface v1 reads:

```text
Commitments/Commitments.md
Decisions/Decisions.md
Open Loops/Open Loops.md
```

It does not scrape arbitrary freeform notes. Completion comes from the Obsidian checkbox in the managed item block for now. Trust is separate: `possible`, missing-status, unknown-owner, and unknown-perspective items are shown as needs-review so they remain useful without becoming official commitments. Accepted items move into actionable lanes while still remaining open until their checkbox is checked. Rejected items remain in notes but are ignored by default surface attention.

## Development

Run the CLI test suite with:

```bash
ruby -Itest -e 'Dir["test/**/*_test.rb"].sort.each { |path| require File.expand_path(path) }'
```

No external Ruby gems are required. Automated tests do not send real notifications and use mock transcription rather than real ML.

## License

Kit is licensed under the Apache License, Version 2.0. See `LICENSE`.
