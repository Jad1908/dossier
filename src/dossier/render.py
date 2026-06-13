"""Assemble sections into the final prompt string (roadmap §5)."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from .sections import MissingFileError, MissingPromptError, render_section_content
from .spec import CsvSection, FileSection, FolderSection, Spec, TextSection


@dataclass
class RenderContext:
    """Resolved inputs that sections need beyond the spec itself.

    `prompts` is the [prompts] library from .dossier/config.toml; `tree_exclude` /
    `tree_include` are the effective tree filters (config + CLI combined).
    """

    prompts: dict[str, str] = field(default_factory=dict)
    tree_exclude: list[str] = field(default_factory=list)
    tree_include: list[str] = field(default_factory=list)


class MissingPathsError(Exception):
    """Raised when one or more `file` paths are missing. Lists all of them."""

    def __init__(self, paths: list[str]) -> None:
        self.paths = paths
        super().__init__("missing file paths: " + ", ".join(paths))


class MissingPromptsError(Exception):
    """Raised when `text` sections reference unknown prompt names."""

    def __init__(self, names: list[str]) -> None:
        self.names = names
        super().__init__("missing prompts: " + ", ".join(names))


def check_missing_paths(spec: Spec, root: Path) -> list[str]:
    """Return every `file`/`csv`/`folder` section path that does not resolve
    under root. `file`/`csv` paths must be files; `folder` paths must be
    directories."""
    missing: list[str] = []
    root_resolved = root.resolve()
    for section in spec.section:
        if isinstance(section, (FileSection, CsvSection, FolderSection)):
            target = (root / section.path).resolve()
            under_root = target == root_resolved or root_resolved in target.parents
            is_right_kind = (
                target.is_dir()
                if isinstance(section, FolderSection)
                else target.is_file()
            )
            if not (target.exists() and is_right_kind and under_root):
                missing.append(section.path)
    return missing


def check_missing_prompts(spec: Spec, ctx: RenderContext) -> list[str]:
    """Return every prompt name referenced by a `text` section but not defined
    in the prompts library."""
    return [
        s.prompt
        for s in spec.section
        if isinstance(s, TextSection)
        and s.prompt is not None
        and s.prompt not in ctx.prompts
    ]


def _wrap(title: str, type_: str, content: str) -> str:
    return f'<section name="{title}" type="{type_}">\n{content}\n</section>'


@dataclass
class RenderedSection:
    """One rendered section: its title, type, and inner content (no envelope)."""

    name: str
    type: str
    content: str


def render_sections(
    spec: Spec, root: Path, ctx: RenderContext | None = None
) -> list[RenderedSection]:
    """Render each section's inner content in order. Hard-fails (collecting all
    problems first, no partial output) on missing `file` paths or unknown prompt
    references — the same contract as `render`.
    """
    ctx = ctx or RenderContext()

    missing = check_missing_paths(spec, root)
    if missing:
        raise MissingPathsError(missing)
    missing_prompts = check_missing_prompts(spec, ctx)
    if missing_prompts:
        raise MissingPromptsError(missing_prompts)

    rendered: list[RenderedSection] = []
    for section in spec.section:
        try:
            content = render_section_content(section, root, ctx)
        except MissingFileError as exc:  # safety net; checked above
            raise MissingPathsError([exc.path]) from exc
        except MissingPromptError as exc:  # safety net; checked above
            raise MissingPromptsError([exc.name]) from exc
        rendered.append(RenderedSection(section.title, section.type, content))
    return rendered


def render(spec: Spec, root: Path, ctx: RenderContext | None = None) -> str:
    """Render the full prompt by wrapping each section in its envelope."""
    return "\n\n".join(
        _wrap(s.name, s.type, s.content) for s in render_sections(spec, root, ctx)
    )
