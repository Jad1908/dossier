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


def _render_csv(section: CsvSection, root: Path) -> str:
    """Header + the first `rows` data rows, narrowed to `columns` when set.

    Column names that don't exist in the header are ignored; if none of the
    requested columns exist, all columns are kept rather than emitting an
    empty table. When rows are cut, a trailing marker says how many were
    omitted, so the model knows it's looking at a sample.
    """
    text = _read_repo_file(section.path, root)
    if section.rows == -1 and not section.columns:
        return text   # whole file, all columns — same as a file section

    reader = csv.reader(io.StringIO(text))
    try:
        header = next(reader)
    except StopIteration:
        return ""

    indices = list(range(len(header)))
    if section.columns:
        wanted = set(section.columns)
        selected = [i for i, name in enumerate(header) if name in wanted]
        if selected:
            indices = selected

    out_rows = [[header[i] for i in indices]]
    omitted = 0
    for n, row in enumerate(reader):
        if section.rows != -1 and n >= section.rows:
            omitted += 1
            continue
        out_rows.append([row[i] if i < len(row) else "" for i in indices])

    buf = io.StringIO()
    csv.writer(buf, lineterminator="\n").writerows(out_rows)
    content = buf.getvalue().rstrip("\n")
    if omitted:
        content += f"\n... ({omitted} more row{'s' if omitted != 1 else ''})"
    return content
