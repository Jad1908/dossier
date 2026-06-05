# ctxforge — v0 Build Roadmap


This document is self-contained. An agent should be able to build the v0 POC from this alone, with no other context.

---

## 1. What this tool is (intent)

`ctxforge` assembles a **structured text prompt** out of pieces of a local codebase, so a developer can hand rich, deliberate context to an AI chat (Claude, ChatGPT) without rebuilding the same prompt by hand every time.

The core design decision: **the prompt is defined by a declarative spec file, not by in-memory selections.** The user writes a `context.toml` describing the sections they want; the tool reads the *current* state of the repo and renders the prompt. When code changes, re-running the tool regenerates the prompt against reality — the spec never goes stale silently.

This is a CLI engine. A GUI may wrap it later but is explicitly **out of scope for v0** (see §8).

The intended user is a developer who wants to stay in control of what enters the model's context window. Optimize for: reproducibility, transparency, and being diffable/commit-able. Do not optimize for cleverness or feature breadth.

---

## 2. Tech stack (fixed)

- **Language:** Python `>=3.11` (uses stdlib `tomllib`, which is 3.11+).
- **Package/dependency manager:** `uv`.
- **CLI framework:** `typer`.
- **Spec validation:** `pydantic` v2.
- **Clipboard:** `pyperclip`.
- **Token counting:** `tiktoken` (single fixed encoding, see §6).
- **Gitignore parsing:** `pathspec`.
- **TOML reading:** stdlib `tomllib` (read-only — the tool never writes TOML in v0).

Do not add dependencies beyond this list without a clear reason.

---

## 3. Project layout

```
ctxforge/
├── pyproject.toml
├── README.md
├── context.toml              # example/working spec at repo root
├── src/
│   └── ctxforge/
│       ├── __init__.py
│       ├── cli.py            # typer app + commands (init, render)
│       ├── spec.py           # pydantic models + TOML loader + validation
│       ├── tree.py           # repo walker (ignore rules + .gitignore)
│       ├── sections.py       # renderers: text / file / tree
│       ├── render.py         # assemble sections into final string
│       ├── parse.py          # round-trip parser (rendered text -> sections)
│       └── tokens.py         # tiktoken-based approximate count
└── tests/
    ├── test_spec.py
    ├── test_render.py
    ├── test_parse.py
    ├── test_tree.py
    └── fixtures/             # tiny sample repo + sample specs
```

---

## 4. The spec file (`context.toml`)

The spec lives at the repo root by default. All file paths inside it are **relative to the repo root**.

### Schema

```toml
# Optional output block. If omitted, defaults below apply.
[output]
copy = true            # copy rendered prompt to clipboard
stdout = true          # also print rendered prompt to stdout
file = ""              # if non-empty, write rendered prompt to this path

# Sections render in the order listed.
[[section]]
type = "tree"
title = "PROJECT STRUCTURE"
max_depth = -1          # -1 = unlimited
use_gitignore = true   # honor the repo's .gitignore in addition to default skips

[[section]]
type = "file"
title = "COLUMN_NAMES SCHEMA"
path = "src/schemas/column_names.py"   # file is READ and its text inlined

[[section]]
type = "text"
title = "REQUEST"
body = "Define a features_names.py schema and update the training config to use it."
```

### Section types (v0 supports exactly these three)

| type   | required fields      | behavior |
|--------|----------------------|----------|
| `text` | `title`, `body`      | Inlines `body` verbatim. For freeform sections (CONTEXT, REQUEST, SYSTEM INSTRUCTIONS). |
| `file` | `title`, `path`      | **Reads the file's text** and inlines it. The path is a source to read, NOT a file to attach. Whole file only — no line ranges in v0. |
| `tree` | `title`              | Generates an ASCII tree of the repo structure. Optional: `max_depth` (int, default _1 = unlimited), `use_gitignore` (bool, default true). |

### Validation rules (pydantic + loader)

- Unknown `type` → error naming the offending section index and the allowed types.
- Missing required field for a type → error naming the section and field.
- `type = "file"` paths are validated for existence at render time, not load time (see §5, hard-fail rule).

---

## 5. Render behavior

### Output format

Each section renders as:

```
<section name="{TITLE}" type="{TYPE}">
{CONTENT}
</section>
```

Sections are joined by a single blank line. The whole output is the prompt.

Rationale for this format: it is **round-trippable**. Because v0 sections do not nest, each `</section>` pairs unambiguously with the preceding open tag, so the rendered text can be parsed back into `(name, type, content)` tuples (see §7). This replaces an earlier lossy format that used an anonymous closer.

**Known limitation (acceptable for v0):** if a source file's own text literally contains the line `</section>`, the round-trip parser will mis-split. Do not solve this in v0; document it in the README.

### Tree generation (`tree.py`)

- Walk from repo root.
- **Always skip** these directories regardless of settings: `.git`, `__pycache__`, `.venv`, `venv`, `node_modules`, `.mypy_cache`, `.pytest_cache`, `.ruff_cache`, `.idea`, `.vscode`, `dist`, `build`, `.DS_Store`.
- If `use_gitignore = true`, additionally skip anything matched by the repo's root `.gitignore`, parsed with `pathspec`. If no `.gitignore` exists, proceed with default skips only.
- Respect `max_depth` (-1 = unlimited).
- Render a clean ASCII tree (`├──`, `└──`, `│`). Directories before files, each level alphabetically sorted.

### Missing-path = hard fail

Before rendering, collect every `type = "file"` path and check it resolves under the repo root. If **any** path is missing:

- Print every missing path (not just the first).
- Exit with a non-zero status code.
- Do NOT produce partial output.

This is deliberate: silent drift is the one real failure mode of the spec-file approach. A hard error turns drift into a signal instead of a stale prompt the user doesn't notice.

---

## 6. Token counting (`tokens.py`)

- Use `tiktoken` with the fixed encoding **`o200k_base`**.
- Count tokens over the full rendered prompt string.
- This is an **estimate only** — token counts differ across model families. Always present it labeled, e.g. `~1,240 tokens (approx, o200k_base)`.
- Print the count to **stderr** (so stdout stays clean for piping the prompt).

Do not attempt multi-tokenizer support in v0.

---

## 7. Round-trip parser (`parse.py`)

Provide a function that parses rendered output back into a list of `(name, type, body)` records:

```python
import re

_SECTION_RE = re.compile(
    r'<section name="(?P<name>[^"]*)" type="(?P<type>[^"]*)">\n'
    r'(?P<body>.*?)\n'
    r'</section>',
    re.DOTALL,
)
```

This exists so the rendered prompt remains machine-readable (it's the contract a future GUI will edit). Note: parsing a `file` or `tree` section recovers the *rendered content*, not the original source path — that is expected and correct. Round-trip losslessness is about section boundaries and labels, not reversing generation.

---

## 8. v0 scope

### In scope
- `context.toml` loading + validation.
- Three section types: `text`, `file`, `tree`.
- Render to the `<section …>…</section>` format.
- Hard-fail on missing `file` paths.
- Approximate token count (stderr).
- Round-trip parser.
- Output: clipboard (default), stdout (default), optional file.
- Two CLI commands: `init`, `render`.

### Explicitly OUT of scope (do not build — these are v1+)
- Any GUI.
- File attachments (images/PDFs/etc.) — text sections only.
- Sub-file / line-range / symbol (AST, tree-sitter) extraction — whole files only.
- Multiple tokenizers.
- File-type conversion of any kind.
- IDE integration.
- Writing or editing the TOML spec programmatically.
- Nested sections.

If a feature is not in the "in scope" list, do not implement it.

---

## 9. CLI surface (`cli.py`, typer)

Global option on all commands: `--root PATH` (defaults to current working directory). The spec path defaults to `<root>/context.toml`, overridable with `--spec PATH`.

### `ctxforge init`
- Writes a starter `context.toml` to the root (a small example with one `tree`, one `text` REQUEST section).
- If `context.toml` already exists, refuse and exit non-zero (do not overwrite).

### `ctxforge render`
- Loads and validates the spec.
- Runs the missing-path check (hard-fail per §5).
- Renders all sections in order.
- Output is governed by the `[output]` block, overridable by flags:
  - `--copy / --no-copy`
  - `--stdout / --no-stdout`
  - `--out PATH` (overrides `[output].file`)
- Prints the token count to stderr.

Exit codes: `0` success; non-zero on validation error or missing paths.

---

## 10. Build phases (each ends with a runnable checkpoint)

### Phase 0 — Scaffold
- `uv init`, create the layout in §3, add dependencies from §2 to `pyproject.toml`.
- Register the `ctxforge` console script entry point.
- **Done when:** `uv run ctxforge --help` prints usage.

### Phase 1 — Spec model + loader (`spec.py`)
- Pydantic models for each section type and the top-level spec.
- Loader reads TOML via `tomllib`, validates, returns typed objects with clear errors.
- **Done when:** `test_spec.py` passes: a valid TOML loads; an unknown type and a missing required field each raise a clear, located error.

### Phase 2 — Renderers (`sections.py`, `tree.py`)
- `text` and `file` renderers (file renderer reads file text; raises on missing path — caught centrally in Phase 3).
- Tree walker with default skips, `.gitignore` support, `max_depth`, sorted output.
- **Done when:** `test_tree.py` passes against the fixture repo (skips applied, depth respected, deterministic ordering).

### Phase 3 — Assembler + parser (`render.py`, `parse.py`)
- Assemble sections into the §5 format.
- Implement the missing-path hard-fail (collect all, then fail).
- Implement the round-trip parser.
- **Done when:** `test_render.py` and `test_parse.py` pass, including the key invariant: for a spec with no `tree`/`file` generation drift, `parse(render(spec))` recovers the same `(name, type, body)` for every section, and a missing `file` path causes a non-zero exit listing all missing paths.

### Phase 4 — Token count (`tokens.py`)
- `o200k_base` count over rendered text, returned as an int; formatting handled by the CLI.
- **Done when:** a unit test confirms a non-zero count for non-empty input and `0` for empty input.

### Phase 5 — CLI wiring (`cli.py`)
- `init` and `render` commands per §9, including clipboard/stdout/file output and stderr token count.
- **Done when:** running `ctxforge init` then `ctxforge render` on the fixture repo copies a correct prompt to the clipboard and prints an `~N tokens (approx, o200k_base)` line to stderr.

### Phase 6 — Docs + dogfood
- Write `README.md`: install, the three section types, the `context.toml` schema, the known `</section>` limitation, example usage.
- Manually run the tool on a real project for a few days; do NOT add features speculatively — let real friction drive v1.
- **Done when:** README is complete and the tool has produced at least one prompt used against a real chat.

---

## 11. Definition of done (v0)

- All phase checkpoints pass.
- `uv run ctxforge init` and `uv run ctxforge render` work end to end on an arbitrary repo.
- Missing `file` paths fail loudly with the full list and a non-zero exit.
- Rendered output round-trips through the parser for section boundaries/labels.
- Token count is shown, labeled approximate, on stderr.
- No out-of-scope features present.
- README documents the schema and the known limitation.

---

## 12. Conventions

- Type hints throughout; run `ruff` for lint/format if available.
- Pure functions where practical: keep I/O (file reads, clipboard, stdout) at the edges (CLI layer), keep `render`/`parse`/`tree` logic side-effect-free and unit-testable.
- Errors are user-facing: messages name the section (by index and title) and the exact problem. No bare tracebacks for expected error conditions.
- Determinism: same repo + same spec → byte-identical output (modulo actual file content changes).
