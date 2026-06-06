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


def _spec(tmp_path: Path, body: str) -> None:
    (tmp_path / "context.toml").write_text(body, encoding="utf-8")


def test_config_output_default_suppresses_stdout(tmp_path: Path):
    # Spec has no [output]; config turns stdout off.
    _spec(tmp_path, '[[section]]\ntype="text"\ntitle="R"\nbody="hello"\n')
    (tmp_path / "dossier.toml").write_text(
        "[output]\nstdout = false\ncopy = false\n", encoding="utf-8"
    )
    result = runner.invoke(app, ["forge", "--root", str(tmp_path)])
    assert result.exit_code == 0
    assert "hello" not in result.output  # prompt not printed
    # CLI flag overrides config back on.
    result2 = runner.invoke(
        app, ["forge", "--root", str(tmp_path), "--stdout", "--no-copy"]
    )
    assert "hello" in result2.output


def test_config_prompt_injection(tmp_path: Path):
    _spec(tmp_path, '[[section]]\ntype="text"\ntitle="R"\nprompt="refactor"\n')
    (tmp_path / "dossier.toml").write_text(
        '[prompts]\nrefactor = "Refactor for readability."\n', encoding="utf-8"
    )
    result = runner.invoke(
        app, ["forge", "--root", str(tmp_path), "--no-copy"]
    )
    assert result.exit_code == 0
    assert "Refactor for readability." in result.output


def test_config_missing_prompt_errors(tmp_path: Path):
    _spec(tmp_path, '[[section]]\ntype="text"\ntitle="R"\nprompt="ghost"\n')
    result = runner.invoke(
        app, ["forge", "--root", str(tmp_path), "--no-copy"]
    )
    assert result.exit_code == 1
    assert "ghost" in result.output


def test_cli_exclude_and_include(tmp_path: Path):
    (tmp_path / "keep").mkdir()
    (tmp_path / "keep" / "a.py").write_text("x", encoding="utf-8")
    (tmp_path / "drop").mkdir()
    (tmp_path / "drop" / "b.py").write_text("x", encoding="utf-8")
    _spec(tmp_path, '[[section]]\ntype="tree"\ntitle="T"\n')

    result = runner.invoke(
        app, ["forge", "--root", str(tmp_path), "--no-copy", "--exclude", "drop"]
    )
    assert "keep" in result.output and "drop" not in result.output

    # __pycache__ is always skipped; --include forces it.
    (tmp_path / "__pycache__").mkdir()
    (tmp_path / "__pycache__" / "c.pyc").write_text("x", encoding="utf-8")
    result2 = runner.invoke(
        app,
        ["forge", "--root", str(tmp_path), "--no-copy", "--include", "__pycache__"],
    )
    assert "__pycache__" in result2.output
