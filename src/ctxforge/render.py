"""Assemble sections into the final prompt string (roadmap §5)."""

from __future__ import annotations

from pathlib import Path

from .sections import MissingFileError, render_section_content
from .spec import FileSection, Spec


class MissingPathsError(Exception):
    """Raised when one or more `file` paths are missing. Lists all of them."""

    def __init__(self, paths: list[str]) -> None:
        self.paths = paths
        super().__init__("missing file paths: " + ", ".join(paths))


def check_missing_paths(spec: Spec, root: Path) -> list[str]:
    """Return every `file` section path that does not resolve under root."""
    missing: list[str] = []
    root_resolved = root.resolve()
    for section in spec.section:
        if isinstance(section, FileSection):
            target = (root / section.path).resolve()
            ok = (
                target.exists()
                and target.is_file()
                and (target == root_resolved or root_resolved in target.parents)
            )
            if not ok:
                missing.append(section.path)
    return missing


def _wrap(title: str, type_: str, content: str) -> str:
    return f'<section name="{title}" type="{type_}">\n{content}\n</section>'


def render(spec: Spec, root: Path) -> str:
    """Render the full prompt. Hard-fails (MissingPathsError) if any `file`
    path is missing — collecting all missing paths first, no partial output.
    """
    missing = check_missing_paths(spec, root)
    if missing:
        raise MissingPathsError(missing)

    parts: list[str] = []
    for section in spec.section:
        try:
            content = render_section_content(section, root)
        except MissingFileError as exc:
            # Should not happen after check_missing_paths, but stay safe.
            raise MissingPathsError([exc.path]) from exc
        parts.append(_wrap(section.title, section.type, content))

    return "\n\n".join(parts)
