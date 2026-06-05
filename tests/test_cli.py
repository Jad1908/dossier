from pathlib import Path

from typer.testing import CliRunner

from dossier.cli import app

runner = CliRunner()


def test_init_default_writes_context_toml(tmp_path: Path):
    result = runner.invoke(app, ["init", "--root", str(tmp_path)])
    assert result.exit_code == 0
    assert (tmp_path / "context.toml").exists()


def test_init_named_writes_context_name_toml(tmp_path: Path):
    result = runner.invoke(app, ["init", "auth", "--root", str(tmp_path)])
    assert result.exit_code == 0
    assert (tmp_path / "context.auth.toml").exists()
    assert not (tmp_path / "context.toml").exists()


def test_init_refuses_overwrite_named(tmp_path: Path):
    (tmp_path / "context.api.toml").write_text("x", encoding="utf-8")
    result = runner.invoke(app, ["init", "api", "--root", str(tmp_path)])
    assert result.exit_code == 1
    assert "refusing to overwrite" in result.output


def test_forge_named_reads_matching_file(tmp_path: Path):
    runner.invoke(app, ["init", "auth", "--root", str(tmp_path)])
    result = runner.invoke(
        app, ["forge", "auth", "--root", str(tmp_path), "--no-copy"]
    )
    assert result.exit_code == 0
    assert 'type="tree"' in result.output


def test_forge_default_when_no_name(tmp_path: Path):
    runner.invoke(app, ["init", "--root", str(tmp_path)])
    result = runner.invoke(app, ["forge", "--root", str(tmp_path), "--no-copy"])
    assert result.exit_code == 0


def test_explicit_spec_overrides_name(tmp_path: Path):
    runner.invoke(app, ["init", "real", "--root", str(tmp_path)])
    spec = tmp_path / "context.real.toml"
    result = runner.invoke(
        app,
        ["forge", "ignored", "--root", str(tmp_path),
         "--spec", str(spec), "--no-copy"],
    )
    assert result.exit_code == 0


def test_forge_missing_named_spec_errors(tmp_path: Path):
    result = runner.invoke(
        app, ["forge", "nope", "--root", str(tmp_path), "--no-copy"]
    )
    assert result.exit_code == 1
    assert "context.nope.toml" in result.output
