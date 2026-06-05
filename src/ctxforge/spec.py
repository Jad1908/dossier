"""Pydantic models + TOML loader for the context.toml spec.

All file paths in the spec are relative to the repo root. Paths are not
checked for existence here — `file` paths are validated at render time (see
the hard-fail rule in the roadmap §5).
"""

from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Annotated, Literal, Union

from pydantic import BaseModel, ConfigDict, Field, ValidationError

ALLOWED_TYPES = ("text", "file", "tree")


class SpecError(Exception):
    """Raised for any spec loading/validation problem. Message is user-facing."""


class _SectionBase(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str


class TextSection(_SectionBase):
    type: Literal["text"]
    body: str


class FileSection(_SectionBase):
    type: Literal["file"]
    path: str


class TreeSection(_SectionBase):
    type: Literal["tree"]
    # 0 = unlimited (per schema default); -1 is also treated as unlimited.
    max_depth: int = 0
    use_gitignore: bool = True


Section = Annotated[
    Union[TextSection, FileSection, TreeSection],
    Field(discriminator="type"),
]


class OutputConfig(BaseModel):
    # `copy` would shadow BaseModel.copy, so the attribute is named
    # `to_clipboard` and aliased to the `copy` TOML key.
    model_config = ConfigDict(extra="forbid", populate_by_name=True)
    to_clipboard: bool = Field(default=True, alias="copy")
    stdout: bool = True
    file: str = ""


class Spec(BaseModel):
    model_config = ConfigDict(extra="forbid")
    output: OutputConfig = Field(default_factory=OutputConfig)
    section: list[Section] = Field(default_factory=list)


def _raise_located(exc: ValidationError, raw_sections: list[dict]) -> None:
    """Translate a pydantic ValidationError into a clear, located SpecError."""
    messages: list[str] = []
    for err in exc.errors():
        loc = err["loc"]
        # Section-level errors look like ("section", <index>, ...).
        if len(loc) >= 2 and loc[0] == "section" and isinstance(loc[1], int):
            idx = loc[1]
            raw = raw_sections[idx] if idx < len(raw_sections) else {}
            title = raw.get("title", "<no title>")
            stype = raw.get("type")
            label = f'section[{idx}] (title={title!r})'

            if stype is not None and stype not in ALLOWED_TYPES:
                messages.append(
                    f"{label}: unknown type {stype!r}; "
                    f"allowed types are {', '.join(ALLOWED_TYPES)}."
                )
                continue

            field = loc[-1] if len(loc) > 2 else "<section>"
            etype = err.get("type", "")
            if etype == "missing":
                messages.append(
                    f"{label}: missing required field {field!r} "
                    f"for type {stype!r}."
                )
            elif etype == "extra_forbidden":
                messages.append(
                    f"{label}: unexpected field {field!r} for type {stype!r}."
                )
            else:
                messages.append(f"{label}: field {field!r}: {err['msg']}.")
        else:
            where = ".".join(str(p) for p in loc) or "<root>"
            messages.append(f"{where}: {err['msg']}.")
    raise SpecError("\n".join(messages))


def load_spec(spec_path: Path) -> Spec:
    """Load and validate a context.toml spec, returning typed objects.

    Raises SpecError with a clear, user-facing message on any problem.
    """
    if not spec_path.exists():
        raise SpecError(f"spec file not found: {spec_path}")

    try:
        with spec_path.open("rb") as fh:
            raw = tomllib.load(fh)
    except tomllib.TOMLDecodeError as exc:
        raise SpecError(f"invalid TOML in {spec_path}: {exc}") from exc

    raw_sections = raw.get("section", [])
    if not isinstance(raw_sections, list):
        raise SpecError("'section' must be an array of tables ([[section]]).")

    try:
        return Spec.model_validate(raw)
    except ValidationError as exc:
        _raise_located(exc, raw_sections)
        raise  # unreachable; _raise_located always raises
