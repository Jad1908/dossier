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


def _cells(line: str) -> list[str]:
    return [c.strip() for c in line.strip().strip("|").split("|")]


def test_default_head_is_five_rows(repo: Path):
    out = render(_csv_spec(), repo)
    assert 'name="DATA" type="csv"' in out
    lines = _content(out).splitlines()
    # Header + separator + 5 data rows + omission marker.
    assert len(lines) == 8
    assert _cells(lines[0]) == ["name", "age", "city"]
    assert set(lines[1]) <= {"|", "-", " "}
    assert _cells(lines[2]) == ["ada", "36", "london"]
    assert _cells(lines[6]) == ["donald", "87", "stanford"]
    assert lines[7] == "... (2 more rows)"


def test_table_is_aligned(repo: Path):
    lines = _content(render(_csv_spec(), repo)).splitlines()
    table = lines[:-1]   # all but the omission marker
    assert len({len(line) for line in table}) == 1


def test_custom_row_count(repo: Path):
    lines = _content(render(_csv_spec(rows=2), repo)).splitlines()
    assert len(lines) == 5
    assert _cells(lines[3]) == ["alan", "41", "manchester"]
    assert lines[4] == "... (5 more rows)"


def test_header_only(repo: Path):
    lines = _content(render(_csv_spec(rows=0), repo)).splitlines()
    assert _cells(lines[0]) == ["name", "age", "city"]
    assert set(lines[1]) <= {"|", "-", " "}
    assert lines[2] == "... (7 more rows)"
    assert len(lines) == 3


def test_whole_file(repo: Path):
    lines = _content(render(_csv_spec(rows=-1), repo)).splitlines()
    assert len(lines) == 9   # header + separator + all 7 data rows
    assert _cells(lines[8]) == ["tim", "68", "london"]
    assert "more rows" not in lines[-1]


def test_column_selection(repo: Path):
    lines = _content(render(_csv_spec(rows=2, columns=["city", "name"]), repo)).splitlines()
    # Header order is preserved regardless of selection order.
    assert _cells(lines[0]) == ["name", "city"]
    assert _cells(lines[2]) == ["ada", "london"]
    assert lines[4] == "... (5 more rows)"


def test_unknown_columns_fall_back_to_all(repo: Path):
    lines = _content(render(_csv_spec(rows=1, columns=["nope"]), repo)).splitlines()
    assert _cells(lines[0]) == ["name", "age", "city"]


def test_semicolon_delimiter_is_sniffed(repo: Path):
    (repo / "semi.csv").write_text(
        "name;age;city\nada;36;london\nalan;41;manchester\n", encoding="utf-8"
    )
    spec = Spec(section=[CsvSection(
        type="csv", title="S", path="semi.csv", rows=1, columns=["age"])])
    lines = _content(render(spec, repo)).splitlines()
    assert _cells(lines[0]) == ["age"]
    assert _cells(lines[2]) == ["36"]


def test_tab_delimiter_with_quoted_fields(repo: Path):
    # The schedule-export pattern: tab-delimited, every data cell quoted,
    # slashes and spaces in values. (A real file in this shape defeated
    # csv.Sniffer, which is why sniffing is structural.)
    (repo / "tabs.csv").write_text(
        'Title\tStart\tNotes\n'
        '"Vacances d\'Été - Zones A/B/C"\t"04.07.2026"\t""\n'
        '"Pont de l\'Ascension"\t"14.05.2026"\t""\n',
        encoding="utf-8",
    )
    spec = Spec(section=[CsvSection(
        type="csv", title="T", path="tabs.csv", rows=1, columns=["Start"])])
    lines = _content(render(spec, repo)).splitlines()
    assert _cells(lines[0]) == ["Start"]
    assert _cells(lines[2]) == ["04.07.2026"]


def test_commas_inside_quotes_dont_fool_the_sniffer(repo: Path):
    # Semicolon-delimited, but every row carries quoted commas — a naive
    # count would pick comma; consistency scoring keeps the semicolon.
    (repo / "tricky.csv").write_text(
        'name;notes\nada;"loves maths, logic"\nalan;"machines, minds"\n',
        encoding="utf-8",
    )
    spec = Spec(section=[CsvSection(type="csv", title="T", path="tricky.csv")])
    lines = _content(render(spec, repo)).splitlines()
    assert _cells(lines[0]) == ["name", "notes"]
    assert _cells(lines[2]) == ["ada", "loves maths, logic"]


def test_cr_only_line_endings(repo: Path):
    (repo / "cr.csv").write_bytes(b"a,b\r1,2\r3,4\r")
    spec = Spec(section=[CsvSection(type="csv", title="C", path="cr.csv", rows=1)])
    lines = _content(render(spec, repo)).splitlines()
    assert _cells(lines[0]) == ["a", "b"]
    assert _cells(lines[2]) == ["1", "2"]
    assert lines[3] == "... (1 more row)"


def test_bom_is_stripped(repo: Path):
    (repo / "bom.csv").write_text("﻿name,age\nada,36\n", encoding="utf-8")
    spec = Spec(section=[CsvSection(
        type="csv", title="B", path="bom.csv", columns=["name"])])
    lines = _content(render(spec, repo)).splitlines()
    assert _cells(lines[0]) == ["name"]


def test_pipes_in_cells_are_escaped(repo: Path):
    (repo / "pipes.csv").write_text('a,b\n"x|y",2\n', encoding="utf-8")
    spec = Spec(section=[CsvSection(type="csv", title="P", path="pipes.csv")])
    content = _content(render(spec, repo))
    assert "x\\|y" in content


def test_short_rows_pad_missing_cells(repo: Path):
    (repo / "ragged.csv").write_text("a,b\n1\n", encoding="utf-8")
    spec = Spec(section=[CsvSection(type="csv", title="R", path="ragged.csv")])
    lines = _content(render(spec, repo)).splitlines()
    assert _cells(lines[2]) == ["1", ""]


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
