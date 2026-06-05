"""Per-section content renderers (text / file / tree).

These produce the *inner content* of a section. Wrapping each in the
<section …>…</section> envelope is done by render.py.
"""

from __future__ import annotations

from pathlib import Path

from .spec import FileSection, Section, TextSection, TreeSection
from .tree import build_tree


class MissingFileError(Exception):
    """Raised when a `file` section's path does not resolve under the root."""

    def __init__(self, path: str) -> None:
        self.path = path
        super().__init__(path)


def render_section_content(section: Section, root: Path) -> str:
    """Render the inner content for a single section.

    May raise MissingFileError for `file` sections with a missing path; the
    assembler collects these for the hard-fail check.
    """
    if isinstance(section, TextSection):
        return section.body
    if isinstance(section, FileSection):
        return _render_file(section, root)
    if isinstance(section, TreeSection):
        return build_tree(
            root,
            max_depth=section.max_depth,
            use_gitignore=section.use_gitignore,
        )
    raise TypeError(f"unknown section type: {type(section).__name__}")


def _render_file(section: FileSection, root: Path) -> str:
    target = (root / section.path).resolve()
    root_resolved = root.resolve()
    # Must exist and resolve under the repo root.
    if not target.exists() or not target.is_file():
        raise MissingFileError(section.path)
    if root_resolved not in target.parents and target != root_resolved:
        raise MissingFileError(section.path)
    return target.read_text(encoding="utf-8", errors="replace")
