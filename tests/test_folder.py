import textwrap
from pathlib import Path

import pytest

from dossier.render import MissingPathsError, render
from dossier.report import build_result
from dossier.spec import FolderSection, Spec, SpecError, load_spec

CSV = (
    "name,age\n"
    "ada,36\n"
    "alan,41\n"
    "grace,52\n"
    "edsger,71\n"
    "donald,87\n"
    "barbara,82\n"
)


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    pkg = tmp_path / "pkg"
    (pkg / "sub").mkdir(parents=True)
    (pkg / "a.py").write_text("print('a')\n", encoding="utf-8")
    (pkg / "sub" / "b.py").write_text("print('b')\n", encoding="utf-8")
    (pkg / "data.csv").write_text(CSV, encoding="utf-8")
    # A binary file: NUL byte makes it undecodable.
    (pkg / "blob.parquet").write_bytes(b"PAR1\x00\x01\x02binary\xff")
    return tmp_path


def _folder_spec(**kwargs) -> Spec:
    return Spec(section=[FolderSection(
        type="folder", title="PKG", path="pkg", **kwargs)])


def _content(out: str) -> str:
    body = out.split(">\n", 1)[1]
    return body.rsplit("\n</section>", 1)[0]


def test_joins_every_file_with_subheaders(repo: Path):
    out = render(_folder_spec(), repo)
    assert 'name="PKG" type="folder"' in out
    content = _content(out)
    # Every file gets a subheader with its path relative to the folder.
    assert "## a.py" in content
    assert "## sub/b.py" in content
    assert "## data.csv" in content
    assert "## blob.parquet" in content


def test_text_files_are_inlined(repo: Path):
    content = _content(render(_folder_spec(), repo))
    assert "## a.py\nprint('a')" in content
    assert "## sub/b.py\nprint('b')" in content


def test_subheaders_are_in_sorted_relative_order(repo: Path):
    content = _content(render(_folder_spec(), repo))
    order = [content.index(h) for h in
             ("## a.py", "## blob.parquet", "## data.csv", "## sub/b.py")]
    assert order == sorted(order)


def test_csv_uses_head_extractor_defaults(repo: Path):
    content = _content(render(_folder_spec(), repo))
    block = content.split("## data.csv\n", 1)[1].split("\n\n", 1)[0]
    lines = block.splitlines()
    # Header + separator + the default 5 data rows + omission marker.
    assert [c.strip() for c in lines[0].strip("|").split("|")] == ["name", "age"]
    assert lines[-1] == "... (1 more row)"
    assert len(lines) == 8


def test_binary_file_is_presence_only(repo: Path):
    content = _content(render(_folder_spec(), repo))
    # Its subheader is present, immediately followed by the next block's blank
    # line — no inlined bytes.
    block = content.split("## blob.parquet", 1)[1]
    assert block.startswith("\n\n") or block == ""


def test_gitignore_is_honored(repo: Path):
    (repo / ".gitignore").write_text("*.csv\n", encoding="utf-8")
    content = _content(render(_folder_spec(), repo))
    assert "## data.csv" not in content
    assert "## a.py" in content


def test_gitignore_can_be_disabled(repo: Path):
    (repo / ".gitignore").write_text("*.csv\n", encoding="utf-8")
    content = _content(render(_folder_spec(use_gitignore=False), repo))
    assert "## data.csv" in content


def test_always_skip_dirs_are_dropped(repo: Path):
    junk = repo / "pkg" / "__pycache__"
    junk.mkdir()
    (junk / "a.cpython.pyc").write_text("noise", encoding="utf-8")
    content = _content(render(_folder_spec(), repo))
    assert "__pycache__" not in content


def test_empty_folder_renders_empty(repo: Path):
    (repo / "empty").mkdir()
    spec = Spec(section=[FolderSection(
        type="folder", title="E", path="empty")])
    assert _content(render(spec, repo)) == ""


def test_missing_folder_hard_fails(repo: Path):
    spec = Spec(section=[FolderSection(
        type="folder", title="G", path="gone")])
    with pytest.raises(MissingPathsError) as exc:
        render(spec, repo)
    assert exc.value.paths == ["gone"]


def test_file_path_is_rejected_as_folder(repo: Path):
    # Pointing a folder section at a file is a missing-path error.
    spec = Spec(section=[FolderSection(
        type="folder", title="F", path="pkg/a.py")])
    with pytest.raises(MissingPathsError) as exc:
        render(spec, repo)
    assert exc.value.paths == ["pkg/a.py"]


def test_path_escape_is_rejected(repo: Path):
    spec = Spec(section=[FolderSection(
        type="folder", title="X", path="../outside")])
    with pytest.raises(MissingPathsError):
        render(spec, repo)


def test_forge_reports_missing_folder_as_missing_file(repo: Path):
    spec_path = repo / ".dossier" / "context.toml"
    spec_path.parent.mkdir()
    spec_path.write_text(
        '[[section]]\ntype="folder"\ntitle="GONE"\npath="nope"\n', encoding="utf-8"
    )
    result = build_result(spec_path, repo / ".dossier" / "config.toml", repo)
    assert result.ok is False
    assert result.errors[0].kind == "missing_file"
    assert result.errors[0].detail == "nope"
    assert result.errors[0].section == "GONE"


def test_forge_renders_folder_ok(repo: Path):
    spec_path = repo / ".dossier" / "context.toml"
    spec_path.parent.mkdir()
    spec_path.write_text(
        '[[section]]\ntype="folder"\ntitle="PKG"\npath="pkg"\n', encoding="utf-8"
    )
    result = build_result(spec_path, repo / ".dossier" / "config.toml", repo)
    assert result.ok is True
    assert result.sections[0].type == "folder"
    assert "## a.py" in result.sections[0].content


def test_spec_loads_folder_section(tmp_path: Path):
    (tmp_path / "context.toml").write_text(
        textwrap.dedent(
            """
            [[section]]
            type = "folder"
            title = "PKG"
            path = "pkg"
            use_gitignore = false
            """
        ),
        encoding="utf-8",
    )
    section = load_spec(tmp_path / "context.toml").section[0]
    assert isinstance(section, FolderSection)
    assert section.path == "pkg"
    assert section.use_gitignore is False


def test_spec_folder_defaults(tmp_path: Path):
    (tmp_path / "context.toml").write_text(
        '[[section]]\ntype="folder"\ntitle="PKG"\npath="pkg"\n',
        encoding="utf-8",
    )
    section = load_spec(tmp_path / "context.toml").section[0]
    assert section.use_gitignore is True


def test_unknown_field_rejected(tmp_path: Path):
    (tmp_path / "context.toml").write_text(
        '[[section]]\ntype="folder"\ntitle="PKG"\npath="pkg"\nrows=3\n',
        encoding="utf-8",
    )
    with pytest.raises(SpecError) as exc:
        load_spec(tmp_path / "context.toml")
    assert "rows" in str(exc.value)
