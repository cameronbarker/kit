# Kit

`kit` is a personal leadership toolkit for engineering managers.

It turns conversations, notes, calendar context, and work signals into commitments, reminders, briefs, prep, and reflection. Its first job is simple: help a manager remember what they said they would do and close loops reliably.

`kit` is not an AI manager. It does not replace judgment, coaching, trust, accountability, or human decision-making.

## Current Status

This repository currently contains the first root-level `kit` CLI skeleton. The CLI is a north star for the intended command surface; most commands are planned but not implemented yet.

The existing `Listen/` prototype is intentionally ignored by the root repo for now while the new project starts with the first-class `kit` command.

## Usage

Run the CLI from the repository root:

```bash
bin/kit help
bin/kit version
```

The current help output describes the intended workflow:

```text
listen -> notice -> remember -> surface -> prepare/brief/followup -> reflect
```

## Commands

```text
listen      Record and transcribe conversations
notice      Extract commitments, decisions, risks, and open loops
remember    Write reviewed items into Obsidian/PARA
surface     Show what needs attention now
prepare     Build context packs for meetings and 1:1s
brief       Draft leadership and stakeholder updates
followup    Track promises, waiting-on items, and stale loops
reflect     Review patterns over time
qmd         Manage/search the local qmd index
```

Planned commands currently return an intentional "not implemented yet" message.

## Development

Run the CLI test suite with:

```bash
ruby test/kit_cli_test.rb
```

No external dependencies are required for the current CLI skeleton beyond Ruby and its standard library.

## Project Notes

See [`kit-one-sheet.md`](kit-one-sheet.md) for the broader product vision, workflow, and guardrails.
