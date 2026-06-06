"""typer CLI: `dossier init` and `dossier forge`.

I/O lives here (file reads at the edges, clipboard, stdout/stderr); the
render/parse/tree logic stays pure and testable.
"""

from __future__ import annotations

from pathlib import Path
from typing import List, Optional

import typer

from .config import CONFIG_FILENAME, DossierConfig, load_config
from .render import MissingPathsError, MissingPromptsError, RenderContext
from .render import render as render_prompt
from .spec import OutputConfig, SpecError, Spec, load_spec
from .tokens import ENCODING_NAME, count_tokens

app = typer.Typer(
    help="Assemble a structured text prompt from a local codebase.",
    no_args_is_help=True,
    add_completion=False,
)

_STARTER_SPEC = """\
# dossier spec — see README for the full schema.

[output]
copy = true
stdout = true
file = ""

[[section]]
type = "tree"
title = "PROJECT STRUCTURE"
max_depth = -1
use_gitignore = true

[[section]]
type = "text"
title = "REQUEST"
body = "Describe what you want the assistant to do here."
"""


def _err(message: str) -> None:
    typer.echo(message, err=True)


def _spec_path(root: Path, spec: Optional[Path], name: Optional[str]) -> Path:
    """Resolve which spec file to use.

    Precedence: an explicit --spec path wins; otherwise a positional NAME maps
    to context.<name>.toml; otherwise the default context.toml.
    """
    if spec is not None:
        return spec
    if name:
        return root / f"context.{name}.toml"
    return root / "context.toml"


def _effective_output(spec: Spec, config: DossierConfig) -> OutputConfig:
    """Merge output settings: config [output] < spec [output] (defaults win
    only where neither set a value). CLI flags are applied by the caller."""
    eff = OutputConfig()  # built-in defaults
    if config.output is not None:
        for f in config.output.model_fields_set:
            setattr(eff, f, getattr(config.output, f))
    for f in spec.output.model_fields_set:
        setattr(eff, f, getattr(spec.output, f))
    return eff


@app.command()
def init(
    name: Optional[str] = typer.Argument(
        None,
        help="Spec name; writes context.<name>.toml (default: context.toml).",
    ),
    root: Path = typer.Option(
        Path.cwd(), "--root", help="Repo root (defaults to cwd)."
    ),
    spec: Optional[Path] = typer.Option(
        None, "--spec", help="Explicit spec path (overrides NAME)."
    ),
) -> None:
    """Write a starter context spec. Refuses to overwrite an existing one."""
    target = _spec_path(root, spec, name)
    if target.exists():
        _err(f"refusing to overwrite existing spec: {target}")
        raise typer.Exit(code=1)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(_STARTER_SPEC, encoding="utf-8")
    typer.echo(f"wrote starter spec: {target}")


@app.command()
def forge(
    name: Optional[str] = typer.Argument(
        None,
        help="Spec name; reads context.<name>.toml (default: context.toml).",
    ),
    root: Path = typer.Option(
        Path.cwd(), "--root", help="Repo root (defaults to cwd)."
    ),
    spec: Optional[Path] = typer.Option(
        None, "--spec", help="Explicit spec path (overrides NAME)."
    ),
    config: Optional[Path] = typer.Option(
        None, "--config", help=f"Config path (defaults to <root>/{CONFIG_FILENAME})."
    ),
    include: Optional[List[str]] = typer.Option(
        None, "--include", help="Force-show a dir/glob in the tree (repeatable)."
    ),
    exclude: Optional[List[str]] = typer.Option(
        None, "--exclude", help="Skip a dir/glob in the tree (repeatable)."
    ),
    copy: Optional[bool] = typer.Option(
        None, "--copy/--no-copy", help="Copy forged prompt to clipboard."
    ),
    stdout: Optional[bool] = typer.Option(
        None, "--stdout/--no-stdout", help="Print forged prompt to stdout."
    ),
    out: Optional[Path] = typer.Option(
        None, "--out", help="Write forged prompt to this path."
    ),
) -> None:
    """Forge the prompt from the spec."""
    spec_path = _spec_path(root, spec, name)
    config_path = config if config is not None else root / CONFIG_FILENAME

    try:
        loaded = load_spec(spec_path)
        cfg = load_config(config_path, required=config is not None)
    except SpecError as exc:
        _err(f"spec error:\n{exc}")
        raise typer.Exit(code=1)

    ctx = RenderContext(
        prompts=cfg.prompts,
        tree_exclude=list(cfg.tree.exclude) + list(exclude or []),
        tree_include=list(cfg.tree.include) + list(include or []),
    )

    try:
        prompt = render_prompt(loaded, root, ctx)
    except MissingPathsError as exc:
        _err("error: missing file paths (no output produced):")
        for p in exc.paths:
            _err(f"  - {p}")
        raise typer.Exit(code=1)
    except MissingPromptsError as exc:
        _err("error: unknown prompt names (no output produced):")
        for n in exc.names:
            _err(f"  - {n} (not in [prompts] of {config_path.name})")
        raise typer.Exit(code=1)

    # Resolve output settings: config < spec < CLI flags.
    eff = _effective_output(loaded, cfg)
    do_copy = eff.to_clipboard if copy is None else copy
    do_stdout = eff.stdout if stdout is None else stdout
    out_file = out if out is not None else (
        Path(eff.file) if eff.file else None
    )

    if out_file is not None:
        out_path = out_file if out_file.is_absolute() else root / out_file
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(prompt, encoding="utf-8")
        _err(f"wrote prompt: {out_path}")

    if do_copy:
        _copy_to_clipboard(prompt)

    if do_stdout:
        typer.echo(prompt)

    tokens = count_tokens(prompt)
    _err(f"~{tokens:,} tokens (approx, {ENCODING_NAME})")


def _copy_to_clipboard(text: str) -> None:
    try:
        import pyperclip

        pyperclip.copy(text)
    except Exception as exc:  # clipboard unavailable (e.g. headless)
        _err(f"warning: could not copy to clipboard: {exc}")


if __name__ == "__main__":
    app()
