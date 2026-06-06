# dossier

Build deliberate, reproducible context for AI chats from your codebase.

`dossier` assembles a structured text prompt out of pieces of a local
repository — a file tree, the full text of specific files, and your own
instructions — so you can hand rich context to an AI assistant (Claude, ChatGPT,
and the like) without reassembling it by hand every time.

The prompt is defined by a declarative spec file, not by ad-hoc copy-paste. You
describe the sections you want once in a `context.toml`; dossier reads the
*current* state of the repo and renders the prompt. When the code changes,
re-running regenerates the prompt against reality, so the context you send is
never quietly out of date.

It is a small, transparent CLI. The output is plain text you can read, diff, and
commit.

## Contents

- [Why dossier](#why-dossier)
- [Quick start](#quick-start)
- [Installation](#installation)
- [The spec file](#the-spec-file)
- [Project configuration](#project-configuration)
- [Command reference](#command-reference)
- [Output format](#output-format)
- [Design notes and limitations](#design-notes-and-limitations)
- [Development](#development)

## Why dossier

Pasting code into a chat is easy until you do it ten times a day. The same files,
the same project layout, the same standing instructions — rebuilt by hand,
slightly different each time, and stale the moment you edit a file.

dossier treats your prompt context as a build artifact:

- **Declarative.** A spec lists the sections you want. The tool resolves them
  against the repo at render time.
- **Reproducible.** The same repo and spec produce byte-identical output, so a
  prompt can be regenerated and reviewed like any other generated file.
- **Transparent.** The result is readable text with labelled sections — no
  hidden state, no binary blobs.
- **Honest about drift.** If a referenced file has moved or been deleted, the
  render fails loudly instead of silently shipping a stale prompt.

It is intentionally narrow: it selects and renders text. It does not call any
model, attach files, or extract symbols.

## Quick start

```bash
# Install once, globally (see Installation for alternatives).
uv tool install "git+https://github.com/Jad1908/dossier.git"

# In any project:
cd ~/code/myapp
dossier init        # writes a starter context.toml
$EDITOR context.toml
dossier forge       # renders the prompt and copies it to your clipboard
```

A `context.toml` like this:

```toml
[[section]]
type = "tree"
title = "PROJECT STRUCTURE"

[[section]]
type = "file"
title = "AUTH MODULE"
path = "src/app/auth.py"

[[section]]
type = "text"
title = "REQUEST"
body = "Add rate limiting to the login endpoint. Keep the existing API shape."
```

produces a prompt like this:

```
<section name="PROJECT STRUCTURE" type="tree">
myapp
├── src
│   └── app
│       ├── auth.py
│       └── main.py
└── pyproject.toml
</section>

<section name="AUTH MODULE" type="file">
def login(username, password):
    ...
</section>

<section name="REQUEST" type="text">
Add rate limiting to the login endpoint. Keep the existing API shape.
</section>
```

Paste it into your assistant of choice. Commit the `context.toml` so the prompt
is reproducible, and re-run `dossier forge` whenever the code moves on.

## Installation

dossier requires Python 3.11 or newer and [uv](https://docs.astral.sh/uv/).

### As a global command

This is the recommended setup for day-to-day use across many projects:

```bash
# Straight from GitHub:
uv tool install "git+https://github.com/Jad1908/dossier.git"

# Or from a local clone (use --editable to track your changes):
uv tool install --editable /path/to/dossier
```

`dossier` is then available from any directory. If the command is not found
afterwards, run `uv tool update-shell` once and restart your shell. To update or
remove it later:

```bash
uv tool upgrade dossier
uv tool uninstall dossier
```

### Without installing

Run it on demand from a clone, pointing `--root` at the project you want to
forge a prompt for:

```bash
uvx --from /path/to/dossier dossier forge --root ~/code/myapp
```

### From a clone, for development

```bash
git clone https://github.com/Jad1908/dossier.git
cd dossier
uv sync
uv run dossier --help
```

`uv run` resolves against the project's local environment, so the command works
from inside the clone. Use the global install above to run it elsewhere.

## The spec file

A spec is a TOML file — `context.toml` by default — that lives at the root of the
project you are describing. Every path inside it is relative to that root.
Sections render in the order listed.

```toml
[[section]]
type = "tree"
title = "PROJECT STRUCTURE"
max_depth = -1         # -1 = unlimited; 0 = root only; N = descend N levels
use_gitignore = true   # also skip anything in the repo's root .gitignore

[[section]]
type = "file"
title = "COLUMN NAMES SCHEMA"
path = "src/schemas/column_names.py"

[[section]]
type = "text"
title = "REQUEST"
body = "Define a feature_names.py schema and update the training config to use it."
```

### Section types

| Type   | Required                              | What it does                                                                                                   |
|--------|---------------------------------------|----------------------------------------------------------------------------------------------------------------|
| `text` | `title`, and one of `body` / `prompt` | Inserts text. Use `body` for inline text, or `prompt` to pull a reusable prompt from your config by name.       |
| `file` | `title`, `path`                       | Reads the file at `path` and inlines its text. The whole file is included; `path` is a source to read, not an attachment. |
| `tree` | `title`                               | Renders an ASCII tree of the repository. Optional `max_depth` and `use_gitignore`.                              |

The tree always skips noise directories regardless of settings: `.git`,
`__pycache__`, `.venv`, `venv`, `node_modules`, `.mypy_cache`, `.pytest_cache`,
`.ruff_cache`, `.idea`, `.vscode`, `dist`, `build`, and `.DS_Store`. With
`use_gitignore = true` (the default) it also honours the repository's root
`.gitignore`.

### Writing prompts inline or storing them

A `text` section takes exactly one of `body` or `prompt`:

- `body` puts the text directly in the spec. Best for one-off, spec-specific
  instructions. No config file is needed.
- `prompt` names an entry in the `[prompts]` table of your `dossier.toml`. Best
  for instructions you reuse across specs and projects.

```toml
[[section]]
type = "text"
title = "CONTEXT"
body = """
Multi-line context that only matters for this particular prompt.
"""

[[section]]
type = "text"
title = "REQUEST"
prompt = "refactor"   # resolved from [prompts].refactor in dossier.toml
```

You can mix both styles freely within a single spec.

### Multiple specs in one folder

`init` and `forge` take an optional positional name so you can keep several
specs side by side. A name maps to `context.<name>.toml`; with no name, the
default `context.toml` is used.

```bash
dossier init auth     # writes context.auth.toml
dossier forge auth    # forges from context.auth.toml
dossier forge         # forges from context.toml
```

```
context.toml
context.auth.toml
context.api.toml
```

For a file outside that convention, `--spec PATH` points at an explicit path.

## Project configuration

An optional `dossier.toml` at the project root holds defaults shared across the
spec files in that folder. Every block is optional; without the file, built-in
defaults apply.

```toml
# Default output behaviour. A spec's own [output] overrides this, and CLI
# flags override both.
[output]
copy = true            # copy the forged prompt to the clipboard
stdout = true          # also print it to stdout
file = ""              # if set, write it to this path

# Tree filters applied to every tree section. `exclude` adds skip patterns;
# `include` forces entries back in even when default skips or .gitignore would
# drop them (and reveals the whole subtree underneath). Patterns are globs,
# matched against each entry's name and its repo-relative path.
[tree]
exclude = ["docs", "*.snap"]
include = ["dist"]

# Reusable prompts, referenced from a text section by name.
[prompts]
refactor = "Refactor the code above for readability. Keep behaviour identical."
explain  = "Explain what the code above does, step by step, and flag any bugs."
```

Referencing a prompt that is not defined fails the render and lists the unknown
names, the same way a missing file path does.

### Precedence

- **Output settings:** CLI flags, then the spec's `[output]`, then the config's
  `[output]`, then built-in defaults.
- **Tree filters:** config `[tree]` and the CLI `--include` / `--exclude` flags
  are combined. `include` wins over `exclude`, default skips, and `.gitignore`.

## Command reference

Both commands accept these options:

| Option        | Description                                                       |
|---------------|-------------------------------------------------------------------|
| `--root PATH` | Project root. Defaults to the current working directory.          |
| `--spec PATH` | Explicit spec path. Overrides the positional name.                |

### `dossier init [NAME]`

Writes a starter spec (`context.toml`, or `context.<name>.toml` for a name). It
will not overwrite an existing spec.

### `dossier forge [NAME]`

Renders the prompt from the spec. Additional options:

| Option                    | Description                                                        |
|---------------------------|--------------------------------------------------------------------|
| `--config PATH`           | Config file to load. Defaults to `<root>/dossier.toml`.            |
| `--include PATTERN`       | Force a directory or glob back into the tree. Repeatable.         |
| `--exclude PATTERN`       | Skip a directory or glob in the tree. Repeatable.                 |
| `--copy` / `--no-copy`    | Copy the prompt to the clipboard.                                 |
| `--stdout` / `--no-stdout`| Print the prompt to stdout.                                       |
| `--out PATH`              | Write the prompt to a file.                                       |

A token estimate is printed to stderr (so stdout stays clean for piping), using
`tiktoken`'s `o200k_base` encoding. Token counts vary across model families, so
treat it as an approximation rather than an exact figure.

`forge` exits non-zero, with no output, on a validation error, a missing `file`
path, or an unknown `prompt` reference.

## Output format

Each section is wrapped in a labelled envelope:

```
<section name="{TITLE}" type="{TYPE}">
{CONTENT}
</section>
```

Sections are separated by a blank line. The format is intentionally
round-trippable: a rendered prompt can be parsed back into
`(name, type, content)` records, which keeps the output machine-readable for
tooling built on top of it.

## Design notes and limitations

- **Whole files only.** A `file` section includes the entire file. There is no
  line-range or symbol-level extraction.
- **Single tokenizer.** Counts use `o200k_base` and are approximate.
- **Literal `</section>` lines.** If a source file's own text contains a line
  that is exactly `</section>`, the round-trip parser will mis-split that
  section. Avoid `file` sections on such files if you intend to parse the output
  back.

## Development

```bash
uv sync
uv run pytest
```

The codebase keeps I/O at the edges (the CLI layer) and the rendering, parsing,
and tree-walking logic pure, so most behaviour is covered by fast unit tests.
Issues and pull requests are welcome.
