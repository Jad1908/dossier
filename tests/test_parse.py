from pathlib import Path

from dossier.parse import ParsedSection, parse
from dossier.render import render
from dossier.spec import Spec, TextSection


def test_parse_basic():
    text = (
        '<section name="REQUEST" type="text">\n'
        "do the thing\n"
        "</section>"
    )
    assert parse(text) == [ParsedSection("REQUEST", "text", "do the thing")]


def test_parse_multiple():
    text = (
        '<section name="A" type="text">\n'
        "one\n"
        "</section>\n\n"
        '<section name="B" type="text">\n'
        "two\nlines\n"
        "</section>"
    )
    assert parse(text) == [
        ParsedSection("A", "text", "one"),
        ParsedSection("B", "text", "two\nlines"),
    ]


def test_round_trip_recovers_sections(sample_repo: Path):
    spec = Spec(
        section=[
            TextSection(type="text", title="CONTEXT", body="some context"),
            TextSection(type="text", title="REQUEST", body="multi\nline\nbody"),
        ]
    )
    rendered = render(spec, sample_repo)
    parsed = parse(rendered)
    assert parsed == [
        ParsedSection("CONTEXT", "text", "some context"),
        ParsedSection("REQUEST", "text", "multi\nline\nbody"),
    ]
    # Names and types match the spec exactly.
    for original, recovered in zip(spec.section, parsed):
        assert original.title == recovered.name
        assert original.type == recovered.type
