# Dossier — macOS app

A native macOS front end for the `dossier` CLI: a three-pane editor for a
`context.toml` spec with a live preview of the rendered prompt. The app **never
renders prompts itself** — it edits the spec on disk and shells out to
`dossier forge --format json` for every preview. There is one source of truth
for output (the engine).

See [`../references/DESKTOP_APP_SPEC.md`](../references/DESKTOP_APP_SPEC.md) for
the full build spec and [`../references/DESIGN.md`](../references/DESIGN.md) for
the visual system this is built against.

## Layout

```
app/
├── Package.swift                 # SwiftPM executable target (macOS 14+, TOMLKit)
├── Info.plist                    # bundle metadata for the .app
├── Makefile                      # `make app` → Dossier.app
└── Sources/Dossier/
    ├── App/        DossierApp, AppModel (Observation state), actions
    ├── Theme/      DESIGN.md tokens, component styles, segmented control
    ├── Model/      Spec/ProjectConfig + TOML read/write (SpecIO)
    ├── Engine/     binary lookup + `forge --format json` subprocess
    ├── Explorer/   native file tree (left pane)
    ├── Builder/    section cards (middle pane)
    ├── Preview/    structural outline + full prompt (right pane)
    └── Views/      ContentView, empty/missing states, settings, prompt library
```

> Built as a **Swift package**, not an `.xcodeproj`, so it compiles with the
> Swift toolchain alone (no full Xcode required). The architecture, data model,
> and engine contract are exactly as the spec describes; only the project
> container differs.

## Requirements

- macOS 14 (Sonoma) or newer.
- Swift 5.9+ toolchain (Command Line Tools are enough — `swift build`).
- The `dossier` CLI on your `PATH`. Install it from the repo root:
  ```sh
  uv tool install --force .
  ```
  The app auto-detects the binary (login-shell `PATH`, then the usual install
  locations); you can also set the path in **Settings**.

## Build & run

```sh
cd app
make app      # builds release + assembles Dossier.app
make run      # build, then `open` it
open Dossier.app
```

`swift build` alone produces a bare executable in `.build/`; macOS needs the
`.app` bundle (with `Info.plist`) to run it as a windowed app — that is what
`make app` assembles.

## How it works

- **Spec I/O** — the app reads and writes `context.toml` / `context.<name>.toml`
  and `dossier.toml` with [TOMLKit](https://github.com/LebJe/TOMLKit). Writing
  reserializes the file and **drops hand-written comments** (an accepted v1
  trade-off — app-managed specs are app-managed).
- **Preview** — on each edit the spec is written to disk (debounced ~300 ms) and
  `dossier forge <name> --format json --root <folder>` is run off the main
  thread. The outline shows each section's envelope with `text`/`tree` bodies in
  full and `file` bodies collapsed to a summary chip; **Full prompt** shows the
  materialized text that **Copy** / **Save** emit.
- **Two trees, never conflated** — the left explorer is a raw on-disk folder walk
  (no engine skip rules); a `tree` *section* is the engine's filtered render,
  shown only in the preview.

### One divergence from the spec doc

`DESKTOP_APP_SPEC.md` §5/§6 sketch per-`tree`-section `include`/`exclude` lists.
The engine's `TreeSection` (authoritative — `src/dossier/spec.py`) forbids those
fields; tree filters live in `dossier.toml`'s `[tree]` table. The app follows
the engine: tree cards expose `max_depth` + `use_gitignore`, and the
include/exclude pattern lists are edited in the **Prompt Library** sheet (which
writes `dossier.toml`).

## Contract test

The engine ↔ app JSON contract is guarded at the repo root by
`tests/test_forge_json.py`, which asserts the shape `ForgeResult` decodes.
