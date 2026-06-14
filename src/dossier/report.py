"""Machine-readable forge result (the `--format json` contract).

This module builds the JSON payload the desktop app consumes. It has **no
side effects** — no clipboard, no stdout-prompt, no file writes — and it never
raises for spec/render problems: those are reported inside the result via
`ok=False` and a populated `errors` list, so the app can tell "the engine
failed to run" (a non-zero exit / unparseable output) apart from "the spec has
a fixable error".

The pydantic models here are the source of truth for the JSON shape; the Swift
app mirrors them by hand (DESKTOP_APP_SPEC §5). Keep them in sync.
"""

from __future__ import annotations

from pathlib import Path
from typing import List, Literal, Optional

from pydantic import BaseModel

from .config import load_config
from .render import (
    MissingPathsError,
    MissingPromptsError,
    RenderContext,
    check_missing_paths,
    render_sections,
)
from .spec import (
    CsvSection,
    FileSection,
    FolderSection,
    SpecError,
    TextSection,
    load_spec,
)
from .tokens import ENCODING_NAME, count_tokens

# Stable enum the app can switch on.
ErrorKind = Literal[
    "missing_file",
    "unknown_prompt",
    "invalid_spec",
    "spec_not_found",
    "other",
]


class ForgeError(BaseModel):
    kind: ErrorKind
    detail: str
    # The section title that triggered the error, when one applies.
    section: Optional[str] = None


class SectionResult(BaseModel):
    name: str
    type: str
    content: str


class ForgeResult(BaseModel):
    ok: bool
    prompt: Optional[str] = None
    token_estimate: Optional[int] = None
    encoding: str = ENCODING_NAME
    sections: List[SectionResult] = []
    errors: List[ForgeError] = []


def build_result(
    spec_path: Path,
    config_path: Path,
    root: Path,
    *,
    include: Optional[List[str]] = None,
    exclude: Optional[List[str]] = None,
) -> ForgeResult:
    """Build a ForgeResult for the given spec, never raising for spec/render
    errors. `include`/`exclude` are extra tree filters (e.g. from CLI flags),
    merged on top of the config's."""
    try:
        spec = load_spec(spec_path)
    except SpecError as exc:
        kind: ErrorKind = "spec_not_found" if not spec_path.exists() else "invalid_spec"
        return ForgeResult(ok=False, errors=[ForgeError(kind=kind, detail=str(exc))])

    try:
        cfg = load_config(config_path, required=False)
    except SpecError as exc:
        return ForgeResult(
            ok=False, errors=[ForgeError(kind="invalid_spec", detail=str(exc))]
        )

    ctx = RenderContext(
        prompts=cfg.prompts,
        tree_exclude=list(cfg.tree.exclude) + list(exclude or []),
        tree_include=list(cfg.tree.include) + list(include or []),
    )

    # Collect every fixable error first, in section order, so the app can list
    # them all at once rather than one-at-a-time.
    missing_paths = set(check_missing_paths(spec, root))
    errors: list[ForgeError] = []
    for section in spec.section:
        if (
            isinstance(section, (FileSection, CsvSection, FolderSection))
            and section.path in missing_paths
        ):
            errors.append(
                ForgeError(
                    kind="missing_file", detail=section.path, section=section.title
                )
            )
        elif (
            isinstance(section, TextSection)
            and section.prompt is not None
            and section.prompt not in ctx.prompts
        ):
            errors.append(
                ForgeError(
                    kind="unknown_prompt",
                    detail=section.prompt,
                    section=section.title,
                )
            )
    if errors:
        return ForgeResult(ok=False, errors=errors)

    try:
        rendered = render_sections(spec, root, ctx)
    except (MissingPathsError, MissingPromptsError) as exc:  # safety net
        return ForgeResult(ok=False, errors=[ForgeError(kind="other", detail=str(exc))])

    prompt = "\n\n".join(
        f'<section name="{r.name}" type="{r.type}">\n{r.content}\n</section>'
        for r in rendered
    )
    return ForgeResult(
        ok=True,
        prompt=prompt,
        token_estimate=count_tokens(prompt),
        sections=[
            SectionResult(name=r.name, type=r.type, content=r.content)
            for r in rendered
        ],
    )
