"""Pydantic models + TOML loader for the context.toml spec.

All file paths in the spec are relative to the repo root. Paths are not
checked for existence here — `file` paths are validated at render time (see
the hard-fail rule in the roadmap §5).
"""

from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Annotated, Literal, Optional, Union

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    ValidationError,
    model_validator,
)

ALLOWED_TYPES = ("text", "file", "tree", "csv")


class SpecError(Exception):
    """Raised for any spec loading/validation problem. Message is user-facing."""


class _SectionBase(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str


class TextSection(_SectionBase):
    type: Literal["text"]
    # Exactly one of `body` (inline text) or `prompt` (a name resolved from
    # the [prompts] table in dossier.toml) must be provided.
    body: Optional[str] = None
    prompt: Optional[str] = None

    @model_validator(mode="after")
    def _exactly_one_source(self) -> "TextSection":
        if (self.body is None) == (self.prompt is None):
            raise ValueError(
                "a text section needs exactly one of 'body' or 'prompt'"
            )
        return self


class FileSection(_SectionBase):
    type: Literal["file"]
    path: str


class TreeSection(_SectionBase):
    type: Literal["tree"]
    # -1 = unlimited (the default). 0 = root only; N = descend N levels.
    max_depth: int = -1
    use_gitignore: bool = True


class CsvSection(_SectionBase):
    """A csv head extractor: the header plus the first `rows` data rows,
    optionally narrowed to named columns — a peek at tabular data without
    inlining a whole dataset."""

    type: Literal["csv"]
    path: str
    # Data rows to keep after the header; -1 = the whole file.
    rows: int = 5
    # Column names to keep (header order); empty = all columns.
    columns: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def _rows_in_range(self) -> "CsvSection":
        if self.rows < -1:
            raise ValueError("'rows' must be -1 (whole file) or >= 0")
        return self


Section = Annotated[
    Union[TextSection, FileSection, TreeSection, CsvSection],
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
            elif etype == "value_error":
                # Whole-section rule (e.g. body/prompt mutual exclusion).
                msg = err["msg"].removeprefix("Value error, ")
                messages.append(f"{label}: {msg}.")
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
