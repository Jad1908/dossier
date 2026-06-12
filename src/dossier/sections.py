"""Per-section content renderers (text / file / tree).

These produce the *inner content* of a section. Wrapping each in the
<section …>…</section> envelope is done by render.py.
"""

from __future__ import annotations

import csv
import io
from pathlib import Path
from typing import TYPE_CHECKING

from .spec import CsvSection, FileSection, Section, TextSection, TreeSection
from .tree import build_tree

if TYPE_CHECKING:
    from .render import RenderContext


class MissingFileError(Exception):
    """Raised when a `file` section's path does not resolve under the root."""

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
        return _read_repo_file(section.path, root)
    if isinstance(section, CsvSection):
        return _render_csv(section, root)
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


def _read_repo_file(path: str, root: Path) -> str:
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
    text = _read_repo_file(section.path, root).lstrip("\ufeff")
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
