import textwrap
from pathlib import Path

import pytest

from dossier.config import DossierConfig, load_config
from dossier.render import (
    MissingPromptsError,
    RenderContext,
    check_missing_prompts,
    render,
)
from dossier.spec import Spec, SpecError, TextSection, load_spec


def _write(path: Path, content: str) -> Path:
    path.write_text(textwrap.dedent(content), encoding="utf-8")
    return path


# --- config loading -------------------------------------------------------


def test_missing_config_returns_empty(tmp_path: Path):
    cfg = load_config(tmp_path / "dossier.toml")
    assert cfg == DossierConfig()
    assert cfg.output is None
    assert cfg.prompts == {}
    assert cfg.tree.exclude == [] and cfg.tree.include == []


def test_config_parses_all_blocks(tmp_path: Path):
    p = _write(
        tmp_path / "dossier.toml",
        """
        [output]
        copy = false
        file = "out.txt"

        [tree]
        exclude = ["docs"]
        include = ["dist"]

        [prompts]
        refactor = "Refactor for readability."
        """,
    )
    cfg = load_config(p)
    assert cfg.output is not None
    assert cfg.output.to_clipboard is False
    assert cfg.output.file == "out.txt"
    assert "copy" in {  # alias maps to attribute name
        f for f in cfg.output.model_fields_set
    } or "to_clipboard" in cfg.output.model_fields_set
    assert cfg.tree.exclude == ["docs"] and cfg.tree.include == ["dist"]
    assert cfg.prompts["refactor"] == "Refactor for readability."


def test_malformed_config_raises(tmp_path: Path):
    p = _write(tmp_path / "dossier.toml", "[tree]\nexclude = 5\n")
    with pytest.raises(SpecError):
        load_config(p)


# --- prompt injection -----------------------------------------------------


def test_text_section_prompt_resolves(tmp_path: Path):
    spec = Spec(
        section=[TextSection(type="text", title="REQUEST", prompt="refactor")]
    )
    ctx = RenderContext(prompts={"refactor": "Refactor it."})
    out = render(spec, tmp_path, ctx)
    assert "Refactor it." in out
    assert 'name="REQUEST" type="text"' in out


def test_missing_prompt_hard_fails(tmp_path: Path):
    spec = Spec(
        section=[
            TextSection(type="text", title="A", body="ok"),
            TextSection(type="text", title="B", prompt="nope"),
        ]
    )
    ctx = RenderContext(prompts={})
    assert check_missing_prompts(spec, ctx) == ["nope"]
    with pytest.raises(MissingPromptsError) as exc:
        render(spec, tmp_path, ctx)
    assert exc.value.names == ["nope"]


# --- text section validation ----------------------------------------------


def test_text_requires_exactly_one_source(tmp_path: Path):
    both = _write(
        tmp_path / "context.toml",
        """
        [[section]]
        type = "text"
        title = "BAD"
        body = "x"
        prompt = "y"
        """,
    )
    with pytest.raises(SpecError) as exc:
        load_spec(both)
    assert "exactly one of 'body' or 'prompt'" in str(exc.value)

    neither = _write(
        tmp_path / "context.toml",
        """
        [[section]]
        type = "text"
        title = "BAD"
        """,
    )
    with pytest.raises(SpecError):
        load_spec(neither)
