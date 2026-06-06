"""Project-level config (`dossier.toml`).

Holds defaults that apply across spec files: an `[output]` block, persistent
tree `include`/`exclude` rules, and a `[prompts]` library that text sections
can reference by name. The config is optional — if no file exists, an empty
config (all defaults) is used.

Precedence for output settings:
    CLI flags  >  spec [output]  >  config [output]  >  built-in defaults
"""

from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, ValidationError

from .spec import OutputConfig, SpecError

CONFIG_FILENAME = "dossier.toml"


class TreeConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")
    # Extra patterns to skip, and patterns to force-show despite default skips
    # / .gitignore. Matched against each entry's name and its repo-relative
    # path (glob via fnmatch). `include` wins over `exclude`.
    exclude: list[str] = Field(default_factory=list)
    include: list[str] = Field(default_factory=list)


class DossierConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")
    # None when [output] is absent, so its set fields can be merged correctly.
    output: Optional[OutputConfig] = None
    tree: TreeConfig = Field(default_factory=TreeConfig)
    prompts: dict[str, str] = Field(default_factory=dict)


def load_config(config_path: Path, *, required: bool = False) -> DossierConfig:
    """Load `dossier.toml`. Returns an empty config if the file is absent
    (unless `required`). Raises SpecError with a user-facing message on a
    malformed file.
    """
    if not config_path.exists():
        if required:
            raise SpecError(f"config file not found: {config_path}")
        return DossierConfig()

    try:
        with config_path.open("rb") as fh:
            raw = tomllib.load(fh)
    except tomllib.TOMLDecodeError as exc:
        raise SpecError(f"invalid TOML in {config_path}: {exc}") from exc

    try:
        return DossierConfig.model_validate(raw)
    except ValidationError as exc:
        first = exc.errors()[0]
        where = ".".join(str(p) for p in first["loc"]) or "<root>"
        raise SpecError(f"config error in {config_path}: {where}: {first['msg']}")
