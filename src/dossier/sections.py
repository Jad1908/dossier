"""Per-section content renderers (text / file / tree).

These produce the *inner content* of a section. Wrapping each in the
<section …>…</section> envelope is done by render.py.
"""

from __future__ import annotations

import csv
import io
from pathlib import Path
from typing import TYPE_CHECKING

from .spec import (
    CsvSection,
    FileSection,
    FolderSection,
    Section,
    TextSection,
    TreeSection,
)
from .tree import build_tree, iter_repo_files

if TYPE_CHECKING:
    from .render import RenderContext


class MissingFileError(Exception):
    """Raised when a `file` section's path does not resolve to a file (under the
    repo root, or anywhere on disk when the section is `external`)."""

    def __init__(self, path: str) -> None:
        self.path = path
        super().__init__(path)


class MissingPromptError(Exception):
    """Raised when a `text` section references an unknown prompt name."""

    def __init__(self, name: str) -> None:
        self.name = name
        super().__init__(name)


def render_section_content(
    section: Section, root: Path, ctx: "RenderContext"
) -> str:
    """Render the inner content for a single section.

    May raise MissingFileError / MissingPromptError; the assembler collects
    these for the hard-fail checks.
    """
    if isinstance(section, TextSection):
        return _render_text(section, ctx)
    if isinstance(section, FileSection):
        return _read_file(section.path, root, external=section.external)
    if isinstance(section, CsvSection):
        return _render_csv(section, root)
    if isinstance(section, FolderSection):
        return _render_folder(section, root)
    if isinstance(section, TreeSection):
        return build_tree(
            root,
            max_depth=section.max_depth,
            use_gitignore=section.use_gitignore,
            exclude=ctx.tree_exclude,
            include=ctx.tree_include,
        )
    raise TypeError(f"unknown section type: {type(section).__name__}")


def _render_text(section: TextSection, ctx: "RenderContext") -> str:
    if section.body is not None:
        return section.body
    # Validated upstream: exactly one of body/prompt is set.
    if section.prompt not in ctx.prompts:
        raise MissingPromptError(section.prompt)
    return ctx.prompts[section.prompt]


def _read_file(path: str, root: Path, *, external: bool = False) -> str:
    """Read a section's file as UTF-8 text. Repo files (the default) must resolve
    under `root`; an `external` file is an absolute path read from anywhere on
    disk, with no containment check."""
    if external:
        target = Path(path).expanduser().resolve()
        if not target.is_file():
            raise MissingFileError(path)
        return target.read_text(encoding="utf-8", errors="replace")
    target = (root / path).resolve()
    root_resolved = root.resolve()
    # Must exist and resolve under the repo root.
    if not target.exists() or not target.is_file():
        raise MissingFileError(path)
    if root_resolved not in target.parents and target != root_resolved:
        raise MissingFileError(path)
    return target.read_text(encoding="utf-8", errors="replace")


# Candidate delimiters, in priority order for ties. Excel exports `;` in many
# locales; schedulers and db dumps love tabs and pipes.
_CANDIDATE_DELIMITERS = (",", ";", "\t", "|")


def _sniff_delimiter(sample: str, truncated: bool = False) -> str:
    """Pick the delimiter whose split is widest and most consistent across the
    sample's records.

    Deliberately not csv.Sniffer, which guesses from quoting patterns and
    misfires on real-world exports. This scores structure instead: for each
    candidate, parse the sample and prefer the one where rows agree with the
    header's column count (consistency first, then width). The app's columns
    picker runs the same algorithm, so both sides always agree.
    """
    best = ","
    best_key = (0.0, 0)
    for cand in _CANDIDATE_DELIMITERS:
        try:
            rows: list[list[str]] = []
            for row in csv.reader(io.StringIO(sample), delimiter=cand):
                if row:
                    rows.append(row)
                if len(rows) >= 30:
                    break
        except csv.Error:
            continue
        if truncated and len(rows) > 1:
            rows = rows[:-1]   # the sample cut may have split a record
        if not rows:
            continue
        cols = len(rows[0])
        if cols < 2:
            continue   # no split at all — never beats a real candidate
        consistency = sum(1 for r in rows if len(r) == cols) / len(rows)
        key = (consistency, cols)
        if key > best_key:
            best, best_key = cand, key
    return best


def _markdown_table(header: list[str], rows: list[list[str]]) -> str:
    """An aligned markdown table — readable in the preview, friendly to models."""

    def clean(cell: str) -> str:
        return (
            cell.replace("\r", " ").replace("\n", " ").replace("|", "\\|").strip()
        )

    head = [clean(c) for c in header]
    body = [[clean(c) for c in row] for row in rows]
    widths = [
        max([len(h), 3] + [len(row[i]) for row in body])
        for i, h in enumerate(head)
    ]

    def fmt(cells: list[str]) -> str:
        return "| " + " | ".join(c.ljust(w) for c, w in zip(cells, widths)) + " |"

    lines = [fmt(head), "| " + " | ".join("-" * w for w in widths) + " |"]
    lines += [fmt(row) for row in body]
    return "\n".join(lines)


def _render_csv(section: CsvSection, root: Path) -> str:
    """Header + the first `rows` data rows (0 = header only, -1 = all),
    narrowed to `columns` when set, emitted as an aligned markdown table.

    The delimiter is sniffed (comma, semicolon, tab, pipe) and a UTF-8 BOM is
    tolerated. Column names that don't exist in the header are ignored; if
    none of the requested columns exist, all columns are kept rather than
    emitting an empty table. When rows are cut, a trailing marker says how
    many were omitted, so the model knows it's looking at a sample.
    """
    text = _read_file(section.path, root, external=section.external).lstrip("\ufeff")
    delimiter = _sniff_delimiter(text[:8192], truncated=len(text) > 8192)
    reader = csv.reader(io.StringIO(text), delimiter=delimiter)
    raw_header = next(reader, None)
    if raw_header is None:
        return ""
    header = [name.strip() for name in raw_header]

    indices = list(range(len(header)))
    if section.columns:
        wanted = set(section.columns)
        selected = [i for i, name in enumerate(header) if name in wanted]
        if selected:
            indices = selected

    kept: list[list[str]] = []
    omitted = 0
    for n, row in enumerate(reader):
        if section.rows != -1 and n >= section.rows:
            omitted += 1
            continue
        kept.append([row[i] if i < len(row) else "" for i in indices])

    content = _markdown_table([header[i] for i in indices], kept)
    if omitted:
        content += f"\n... ({omitted} more row{'s' if omitted != 1 else ''})"
    return content


def _decode_text(path: Path) -> str | None:
    """The file's UTF-8 text, or None when it's binary (a NUL byte or any
    non-UTF-8 sequence) — the signal a file is a "non-base" format whose
    presence we note but whose bytes we don't inline."""
    try:
        data = path.read_bytes()
    except OSError:
        return None
    if b"\x00" in data:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def _render_folder(section: FolderSection, root: Path) -> str:
    """Join every file under the folder, each wrapped in a `<file path="…">`
    envelope giving its path relative to the folder. `*.csv` files use the csv
    head extractor at its defaults; binary (or empty) files emit a self-closing
    `<file path="…" />` tag — their presence noted, their bytes not inlined.

    The envelope is the unambiguous counterpart of the section envelope, so the
    app can re-parse the joined files exactly. The skip rules (ALWAYS_SKIP +
    optional .gitignore) match the tree section's, keeping build artifacts and
    vendored trees out.
    """
    root_resolved = root.resolve()
    base = (root / section.path).resolve()
    # Must be an existing directory under the repo root.
    if not base.exists() or not base.is_dir():
        raise MissingFileError(section.path)
    if root_resolved not in base.parents and base != root_resolved:
        raise MissingFileError(section.path)

    blocks: list[str] = []
    for file in iter_repo_files(root, base, use_gitignore=section.use_gitignore):
        rel = file.relative_to(base).as_posix()
        if file.suffix.lower() == ".csv":
            repo_rel = file.relative_to(root_resolved).as_posix()
            body = _render_csv(
                CsvSection(type="csv", title=rel, path=repo_rel), root
            )
        else:
            body = _decode_text(file)
        # Strip a file's trailing newlines so `</file>` sits flush after its
        # content (the envelope adds its own); empty/binary files self-close.
        body = body.rstrip("\n") if body else body
        if body:
            blocks.append(f'<file path="{rel}">\n{body}\n</file>')
        else:
            blocks.append(f'<file path="{rel}" />')
    return "\n\n".join(blocks)
