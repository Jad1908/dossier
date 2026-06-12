import textwrap
from pathlib import Path

import pytest

from dossier.render import MissingPathsError, render
from dossier.spec import CsvSection, Spec, SpecError, load_spec

CSV = (
    "name,age,city\n"
    "ada,36,london\n"
    "alan,41,manchester\n"
    "grace,52,arlington\n"
    "edsger,71,nuenen\n"
    "donald,87,stanford\n"
    "barbara,82,new york\n"
    "tim,68,london\n"
)


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    (tmp_path / "data.csv").write_text(CSV, encoding="utf-8")
    return tmp_path


def _csv_spec(**kwargs) -> Spec:
    return Spec(section=[CsvSection(type="csv", title="DATA", path="data.csv", **kwargs)])


def _content(out: str) -> str:
    body = out.split(">\n", 1)[1]
    return body.rsplit("\n</section>", 1)[0]


def test_default_head_is_five_rows(repo: Path):
    out = render(_csv_spec(), repo)
    assert 'name="DATA" type="csv"' in out
    content = _content(out)
    lines = content.splitlines()
    assert lines[0] == "name,age,city"
    assert lines[1] == "ada,36,london"
    assert lines[5] == "donald,87,stanford"
    # 7 data rows, 5 kept → header + 5 + omission marker.
    assert lines[6] == "... (2 more rows)"
    assert len(lines) == 7


def test_custom_row_count(repo: Path):
    content = _content(render(_csv_spec(rows=2), repo))
    assert content.splitlines() == [
        "name,age,city",
        "ada,36,london",
        "alan,41,manchester",
        "... (5 more rows)",
    ]


def test_whole_file(repo: Path):
    # Raw pass-through, like a file section (trailing newline included).
    content = _content(render(_csv_spec(rows=-1), repo))
    assert content.rstrip("\n") == CSV.rstrip("\n")
    assert "more rows" not in content


def test_column_selection(repo: Path):
    content = _content(render(_csv_spec(rows=2, columns=["city", "name"]), repo))
    # Header order is preserved regardless of selection order.
    assert content.splitlines() == [
        "name,city",
        "ada,london",
        "alan,manchester",
        "... (5 more rows)",
    ]


def test_whole_file_with_columns_still_filters(repo: Path):
    content = _content(render(_csv_spec(rows=-1, columns=["age"]), repo))
    lines = content.splitlines()
    assert lines[0] == "age"
    assert len(lines) == 8  # header + all 7 data rows, no marker


def test_unknown_columns_fall_back_to_all(repo: Path):
    content = _content(render(_csv_spec(rows=1, columns=["nope"]), repo))
    assert content.splitlines()[0] == "name,age,city"


def test_short_rows_pad_missing_cells(repo: Path):
    (repo / "ragged.csv").write_text("a,b\n1\n", encoding="utf-8")
    spec = Spec(section=[CsvSection(type="csv", title="R", path="ragged.csv")])
    assert _content(render(spec, repo)).splitlines() == ["a,b", "1,"]


def test_missing_csv_path_hard_fails(repo: Path):
    spec = Spec(section=[CsvSection(type="csv", title="D", path="gone.csv")])
    with pytest.raises(MissingPathsError) as exc:
        render(spec, repo)
    assert exc.value.paths == ["gone.csv"]


def test_spec_loads_csv_section(tmp_path: Path):
    (tmp_path / "context.toml").write_text(
        textwrap.dedent(
            """
            [[section]]
            type = "csv"
            title = "DATA"
            path = "data.csv"
            rows = 10
            columns = ["name", "age"]
            """
        ),
        encoding="utf-8",
    )
    spec = load_spec(tmp_path / "context.toml")
    section = spec.section[0]
    assert isinstance(section, CsvSection)
    assert section.rows == 10
    assert section.columns == ["name", "age"]


def test_spec_defaults(tmp_path: Path):
    (tmp_path / "context.toml").write_text(
        '[[section]]\ntype="csv"\ntitle="DATA"\npath="data.csv"\n',
        encoding="utf-8",
    )
    section = load_spec(tmp_path / "context.toml").section[0]
    assert section.rows == 5
    assert section.columns == []


def test_rows_below_minus_one_rejected(tmp_path: Path):
    (tmp_path / "context.toml").write_text(
        '[[section]]\ntype="csv"\ntitle="DATA"\npath="data.csv"\nrows=-2\n',
        encoding="utf-8",
    )
    with pytest.raises(SpecError) as exc:
        load_spec(tmp_path / "context.toml")
    assert "rows" in str(exc.value)
