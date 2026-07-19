# Kit

`kit` is a personal leadership toolkit for engineering managers.

It turns conversations, notes, calendar context, and work signals into commitments, reminders, briefs, prep, and reflection. Its first job is simple: help a manager remember what they said they would do and close loops reliably.

`kit` is not an AI manager. It does not replace judgment, coaching, trust, accountability, or human decision-making.

## Current Status

This repository currently contains the first root-level `kit` CLI plus the first integrated `kit listen` implementation. The rest of the command surface remains a north star for the intended workflow.

The old `Listen/` prototype remains ignored as a migration archive because it contains standalone project scaffolding, local recordings/transcripts, a nested `.git`, and generated Python environment artifacts. Useful source, tests, and Python worker files have been migrated into `lib/kit/listen/` and `test/kit/listen/`.

## Usage

Run the CLI from the repository root:

```bash
bin/kit help
bin/kit version
bin/kit listen help
bin/kit listen status --json
bin/kit status --json
bin/kit notify "Review open commitments"
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
notify      Send a simple local Kit notification
status      Show machine-readable Kit app bridge status
notice      Extract commitments, decisions, risks, and open loops
remember    Write reviewed items into Obsidian/PARA
surface     Show what needs attention now
prepare     Build context packs for meetings and 1:1s
brief       Draft leadership and stakeholder updates
followup    Track promises, waiting-on items, and stale loops
reflect     Review patterns over time
qmd         Manage/search the local qmd index
```

The `listen` command is implemented as a local recording and transcription pipeline. It can list ffmpeg audio devices, run chunked background recording sessions, pause/resume/stop an active session, track recording state, show the latest recording metadata, transcribe an existing audio/video file, and re-render transcript artifacts from raw JSON. The older foreground `record` command remains available.

The `notify` command is implemented as a small macOS notification utility backed by `terminal-notifier` and uses `assets/kit-icon.png` as its notification app icon. The `status --json` command exposes a stable app bridge contract for future non-CLI surfaces. Other planned commands currently return an intentional "not implemented yet" message.

## App Bridge

Kit keeps Mac-facing UI thin. Future app surfaces should call stable Kit commands and consume JSON rather than scrape human-readable CLI output.

Current bridge:

```bash
bin/kit status --json
```

The Ruby bridge lives in `lib/kit/app_bridge/`. A native macOS menu bar scaffold lives in `mac/menubar/` and documents how a future helper should integrate with Kit core commands.

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

Mock transcription requires no Python ML install. Real local transcription requires Python 3.11 or 3.12 dependencies from `lib/kit/listen/python/requirements.txt`, ffmpeg on `PATH`, accepted pyannote model terms, and `HF_TOKEN` when warming or using gated diarization models.

## Development

Run the CLI test suite with:

```bash
ruby -Itest -e 'Dir["test/**/*_test.rb"].sort.each { |path| require File.expand_path(path) }'
```

No external Ruby gems are required. Automated tests do not send real notifications and use mock transcription rather than real ML.

## Project Notes

See [`kit-one-sheet.md`](kit-one-sheet.md) for the broader product vision, workflow, and guardrails.
