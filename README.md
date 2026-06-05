# dossier

Assemble a **structured text prompt** out of pieces of a local codebase, so you
can hand rich, deliberate context to an AI chat (Claude, ChatGPT) without
rebuilding the same prompt by hand every time.

The core idea: **the prompt is defined by a declarative spec file, not by
in-memory selections.** You write a `context.toml` describing the sections you
want; dossier reads the *current* state of the repo and forges the prompt.
When code changes, re-running regenerates the prompt against reality — the spec
never goes stale silently.

This is a CLI engine. Optimize for reproducibility, transparency, and being
diffable / commit-able.

## Install

Requires Python `>=3.11` and [`uv`](https://docs.astral.sh/uv/).

### For local development (in this repo)

```bash
uv sync
uv run dossier --help
```

`uv run` resolves against this project's `.venv`, so the `dossier` command only
works from inside this directory. To use the tool in *other* projects, install
it globally (below).

### As a global CLI (use it in any project)

Install dossier as a standalone tool on your PATH with `uv tool install`. Point
it at the repo (clone it first, or use the URL directly):

```bash
# From a local clone:
uv tool install --editable /path/to/dossier

# Or straight from GitHub:
uv tool install "git+https://github.com/Jad1908/dossier.git"
```

`--editable` tracks your local source so code changes take effect without
reinstalling — drop it to pin a frozen copy. If the `dossier` command isn't
found afterward, run `uv tool update-shell` once and restart your shell.

Now `dossier` is available from any directory:

```bash
cd ~/some/other/project
dossier init         # writes a context.toml in THIS project
dossier forge        # forges + copies the prompt to your clipboard
```

To upgrade or remove the global install later:

```bash
uv tool upgrade dossier
uv tool uninstall dossier
```

### Without installing (one-off)

`uvx` runs it from source against any target directory via `--root`, no install:

```bash
uvx --from /path/to/dossier dossier forge --root ~/some/other/project
```

## Usage

Once installed globally, run it from any project root (omit `uv run` if you used
`uv tool install`):

```bash
dossier init       # writes a starter context.toml (won't overwrite)
dossier forge      # forges the prompt from context.toml
```

### Using it in another repo

1. `cd` into the target project and run `dossier init`.
2. Edit that project's `context.toml`: add a `tree` section for structure,
   `file` sections pointing at the specific files you want the model to see
   (paths are relative to that project's root), and a `text` REQUEST describing
   the task.
3. Run `dossier forge` — the prompt is copied to your clipboard. Paste it into
   Claude / ChatGPT.
4. Commit `context.toml` so the prompt is reproducible. Re-forge any time the
   code changes; the spec renders against the *current* state of the repo.

Global options on every command:

- `--root PATH` — repo root (defaults to the current working directory).
- `--spec PATH` — spec path (defaults to `<root>/context.toml`).

`forge` flags override the `[output]` block in the spec:

- `--copy / --no-copy` — copy the forged prompt to the clipboard.
- `--stdout / --no-stdout` — print the forged prompt to stdout.
- `--out PATH` — write the forged prompt to a file.

A token estimate is printed to **stderr** so stdout stays clean for piping.

## The spec file (`context.toml`)

Lives at the repo root by default. All file paths inside it are **relative to
the repo root**.

```toml
# Optional. If omitted, these defaults apply.
[output]
copy = true            # copy forged prompt to clipboard
stdout = true          # also print forged prompt to stdout
file = ""              # if non-empty, write forged prompt to this path

# Sections render in the order listed.
[[section]]
type = "tree"
title = "PROJECT STRUCTURE"
max_depth = 0          # 0 (or -1) = unlimited
use_gitignore = true   # honor the repo's .gitignore in addition to default skips

[[section]]
type = "file"
title = "COLUMN_NAMES SCHEMA"
path = "src/schemas/column_names.py"   # file is READ and its text inlined

[[section]]
type = "text"
title = "REQUEST"
body = "Define a features_names.py schema and update the training config."
```

### Section types

| type   | required fields | behavior |
|--------|-----------------|----------|
| `text` | `title`, `body` | Inlines `body` verbatim. For freeform sections (CONTEXT, REQUEST, SYSTEM INSTRUCTIONS). |
| `file` | `title`, `path` | **Reads the file's text** and inlines it. The path is a source to read, not a file to attach. Whole file only. |
| `tree` | `title`         | Generates an ASCII tree of the repo. Optional: `max_depth` (default 0 = unlimited), `use_gitignore` (default true). |

The tree always skips: `.git`, `__pycache__`, `.venv`, `venv`, `node_modules`,
`.mypy_cache`, `.pytest_cache`, `.ruff_cache`, `.idea`, `.vscode`, `dist`,
`build`, `.DS_Store`. With `use_gitignore = true` it additionally skips anything
matched by the repo's root `.gitignore`.

## Output format

Each section renders as:

```
<section name="{TITLE}" type="{TYPE}">
{CONTENT}
</section>
```

Sections are joined by a single blank line. This format is **round-trippable**:
the forged text can be parsed back into `(name, type, body)` records.

### Missing `file` paths = hard fail

Before forging, every `type = "file"` path is checked. If any is missing,
dossier prints **all** missing paths and exits non-zero **without producing
output**. This turns silent spec drift into a signal instead of a stale prompt.

## Known limitation

If a source file's own text literally contains the line `</section>`, the
round-trip parser will mis-split that section. This is acceptable for v0 and not
worked around — avoid using `file` sections on files that contain that exact
line if you intend to parse the output back.

## Token count

The printed count uses `tiktoken`'s `o200k_base` encoding and is an **estimate
only** — token counts differ across model families. It is labeled approximate
and printed to stderr.
