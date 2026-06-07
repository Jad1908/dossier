"""Contract test for `dossier forge --format json` (DESKTOP_APP_SPEC §3).

Asserts the JSON shape the desktop app's data model depends on. This is the
single place that keeps the hand-synced pydantic and Swift schemas honest.
"""

import json
from pathlib import Path

from typer.testing import CliRunner

from dossier.cli import app

runner = CliRunner()

# Keys every result carries, success or failure.
RESULT_KEYS = {"ok", "prompt", "token_estimate", "encoding", "sections", "errors"}
ERROR_KINDS = {
    "missing_file",
    "unknown_prompt",
    "invalid_spec",
    "spec_not_found",
    "other",
}


def _spec(tmp_path: Path, body: str) -> None:
    (tmp_path / "context.toml").write_text(body, encoding="utf-8")


def _forge_json(tmp_path: Path, *extra: str) -> dict:
    result = runner.invoke(
        app, ["forge", "--root", str(tmp_path), "--format", "json", *extra]
    )
    assert result.exit_code == 0, result.output
    return json.loads(result.output)


def test_json_success_shape(tmp_path: Path):
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "app.py").write_text("print('hi')\n", encoding="utf-8")
    _spec(
        tmp_path,
        '[[section]]\ntype="tree"\ntitle="PROJECT STRUCTURE"\n\n'
        '[[section]]\ntype="file"\ntitle="APP"\npath="src/app.py"\n\n'
        '[[section]]\ntype="text"\ntitle="REQUEST"\nbody="Do the thing."\n',
    )
    data = _forge_json(tmp_path)

    assert set(data) == RESULT_KEYS
    assert data["ok"] is True
    assert data["errors"] == []
    assert data["prompt"] and 'type="tree"' in data["prompt"]
    assert isinstance(data["token_estimate"], int) and data["token_estimate"] > 0
    assert data["encoding"] == "o200k_base"

    names = [s["name"] for s in data["sections"]]
    assert names == ["PROJECT STRUCTURE", "APP", "REQUEST"]
    for s in data["sections"]:
        assert set(s) == {"name", "type", "content"}


def test_json_missing_file_is_error_not_exit(tmp_path: Path):
    _spec(
        tmp_path,
        '[[section]]\ntype="file"\ntitle="AUTH MODULE"\npath="src/app/auth.py"\n',
    )
    data = _forge_json(tmp_path)

    assert data["ok"] is False
    assert data["prompt"] is None
    assert data["token_estimate"] is None
    assert data["encoding"] == "o200k_base"
    assert data["sections"] == []
    assert len(data["errors"]) == 1
    err = data["errors"][0]
    assert err["kind"] == "missing_file"
    assert err["detail"] == "src/app/auth.py"
    assert err["section"] == "AUTH MODULE"


def test_json_no_side_effects(tmp_path: Path):
    # copy=true would normally hit the clipboard; json mode must not.
    _spec(
        tmp_path,
        '[output]\ncopy = true\nstdout = true\n\n'
        '[[section]]\ntype="text"\ntitle="R"\nbody="hello world"\n',
    )
    result = runner.invoke(
        app, ["forge", "--root", str(tmp_path), "--format", "json"]
    )
    assert result.exit_code == 0
    # stdout is *only* the JSON (the prompt is inside it, not echoed raw).
    parsed = json.loads(result.output)
    assert parsed["ok"] is True


def test_json_unknown_prompt(tmp_path: Path):
    _spec(tmp_path, '[[section]]\ntype="text"\ntitle="REQUEST"\nprompt="refactr"\n')
    data = _forge_json(tmp_path)
    assert data["ok"] is False
    assert data["errors"][0]["kind"] == "unknown_prompt"
    assert data["errors"][0]["detail"] == "refactr"
    assert data["errors"][0]["section"] == "REQUEST"


def test_json_spec_not_found(tmp_path: Path):
    data = _forge_json(tmp_path)  # no context.toml written
    assert data["ok"] is False
    assert data["errors"][0]["kind"] == "spec_not_found"


def test_json_invalid_spec(tmp_path: Path):
    _spec(tmp_path, '[[section]]\ntype="wat"\ntitle="X"\n')
    data = _forge_json(tmp_path)
    assert data["ok"] is False
    assert data["errors"][0]["kind"] == "invalid_spec"


def test_all_error_kinds_are_known(tmp_path: Path):
    # Guards the stable enum the Swift app switches on.
    _spec(tmp_path, '[[section]]\ntype="file"\ntitle="X"\npath="nope.py"\n')
    data = _forge_json(tmp_path)
    for err in data["errors"]:
        assert err["kind"] in ERROR_KINDS
