"""Approximate token counting via tiktoken (fixed o200k_base encoding).

This is an estimate only — token counts differ across model families. The
CLI labels it as approximate. (roadmap §6)
"""

from __future__ import annotations

import functools

import tiktoken

ENCODING_NAME = "o200k_base"


@functools.lru_cache(maxsize=1)
def _encoding() -> "tiktoken.Encoding":
    return tiktoken.get_encoding(ENCODING_NAME)


def count_tokens(text: str) -> int:
    """Return the approximate token count for `text` (0 for empty)."""
    if not text:
        return 0
    return len(_encoding().encode(text))
