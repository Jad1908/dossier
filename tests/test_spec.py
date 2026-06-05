import textwrap
from pathlib import Path

import pytest

from dossier.spec import (
    FileSection,
    SpecError,
    TextSection,
    TreeSection,
    load_spec,
)


def _write(tmp_path: Path, content: str) -> Path:
    p = tmp_path / "context.toml"
    p.write_text(textwrap.dedent(content), encoding="utf-8")
    return p


def test_valid_spec_loads(tmp_path: Path):
    spec_path = _write(
        tmp_path,
        """
        [output]
        copy = false
        stdout = true
        file = "out.txt"

        [[section]]
        type = "tree"
        title = "STRUCTURE"
        max_depth = 2
        use_gitignore = false

        [[section]]
        type = "file"
        title = "APP"
        path = "src/app.py"

        [[section]]
        type = "text"
        title = "REQUEST"
        body = "do the thing"
        """,
    )
    spec = load_spec(spec_path)

    assert spec.output.to_clipboard is False
    assert spec.output.file == "out.txt"
    assert len(spec.section) == 3

    tree, file, text = spec.section
    assert isinstance(tree, TreeSection)
    assert tree.max_depth == 2 and tree.use_gitignore is False
    assert isinstance(file, FileSection) and file.path == "src/app.py"
    assert isinstance(text, TextSection) and text.body == "do the thing"


def test_output_defaults(tmp_path: Path):
    spec_path = _write(
        tmp_path,
        """
        [[section]]
        type = "text"
        title = "R"
        body = "x"
        """,
    )
    spec = load_spec(spec_path)
    assert spec.output.to_clipboard is True
    assert spec.output.stdout is True
    assert spec.output.file == ""


def test_unknown_type_errors_with_location(tmp_path: Path):
    spec_path = _write(
        tmp_path,
        """
        [[section]]
        type = "text"
        title = "OK"
        body = "x"

        [[section]]
        type = "diagram"
        title = "BAD"
        """,
    )
    with pytest.raises(SpecError) as exc:
        load_spec(spec_path)
    msg = str(exc.value)
    assert "section[1]" in msg
    assert "diagram" in msg
    assert "text, file, tree" in msg


def test_missing_required_field_errors_with_location(tmp_path: Path):
    spec_path = _write(
        tmp_path,
        """
        [[section]]
        type = "file"
        title = "NEEDS PATH"
        """,
    )
    with pytest.raises(SpecError) as exc:
        load_spec(spec_path)
    msg = str(exc.value)
    assert "section[0]" in msg
    assert "path" in msg
    assert "NEEDS PATH" in msg


def test_missing_spec_file_errors(tmp_path: Path):
    with pytest.raises(SpecError):
        load_spec(tmp_path / "nope.toml")
