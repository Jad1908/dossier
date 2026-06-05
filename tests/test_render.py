from pathlib import Path

import pytest

from ctxforge.render import MissingPathsError, check_missing_paths, render
from ctxforge.spec import FileSection, Spec, TextSection, TreeSection


def test_render_format(sample_repo: Path):
    spec = Spec(
        section=[
            TextSection(type="text", title="REQUEST", body="do the thing"),
        ]
    )
    out = render(spec, sample_repo)
    assert out == (
        '<section name="REQUEST" type="text">\n'
        "do the thing\n"
        "</section>"
    )


def test_sections_joined_by_blank_line(sample_repo: Path):
    spec = Spec(
        section=[
            TextSection(type="text", title="A", body="one"),
            TextSection(type="text", title="B", body="two"),
        ]
    )
    out = render(spec, sample_repo)
    assert "</section>\n\n<section" in out


def test_file_section_inlines_text(sample_repo: Path):
    spec = Spec(
        section=[FileSection(type="file", title="APP", path="src/app.py")]
    )
    out = render(spec, sample_repo)
    assert "hello from sample repo" in out
    assert 'type="file"' in out


def test_tree_section_renders(sample_repo: Path):
    spec = Spec(
        section=[TreeSection(type="tree", title="STRUCTURE")]
    )
    out = render(spec, sample_repo)
    assert 'name="STRUCTURE" type="tree"' in out
    assert "app.py" in out


def test_missing_path_collects_all_and_fails(sample_repo: Path):
    spec = Spec(
        section=[
            FileSection(type="file", title="A", path="src/app.py"),
            FileSection(type="file", title="B", path="src/nope.py"),
            FileSection(type="file", title="C", path="also/missing.py"),
        ]
    )
    missing = check_missing_paths(spec, sample_repo)
    assert missing == ["src/nope.py", "also/missing.py"]

    with pytest.raises(MissingPathsError) as exc:
        render(spec, sample_repo)
    assert exc.value.paths == ["src/nope.py", "also/missing.py"]


def test_no_partial_output_on_missing(sample_repo: Path):
    spec = Spec(
        section=[
            TextSection(type="text", title="A", body="present"),
            FileSection(type="file", title="B", path="src/nope.py"),
        ]
    )
    with pytest.raises(MissingPathsError):
        render(spec, sample_repo)
