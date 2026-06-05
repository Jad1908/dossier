"""Round-trip parser: rendered prompt -> list of (name, type, body) records.

This is the machine-readable contract a future GUI will edit. Parsing a
`file` or `tree` section recovers the *rendered* content, not the source
path — that is expected (roadmap §7).

Known limitation: if a section's content literally contains a line
`</section>`, the split will be wrong. Acceptable for v0; documented in README.
"""

from __future__ import annotations

import re
from typing import NamedTuple

_SECTION_RE = re.compile(
    r'<section name="(?P<name>[^"]*)" type="(?P<type>[^"]*)">\n'
    r"(?P<body>.*?)\n"
    r"</section>",
    re.DOTALL,
)


class ParsedSection(NamedTuple):
    name: str
    type: str
    body: str


def parse(text: str) -> list[ParsedSection]:
    """Parse rendered output back into (name, type, body) records."""
    return [
        ParsedSection(m.group("name"), m.group("type"), m.group("body"))
        for m in _SECTION_RE.finditer(text)
    ]
