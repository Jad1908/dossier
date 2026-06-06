"""Repo walker: builds an ASCII tree honoring default skips and .gitignore.

Side-effect-free except for reading the filesystem under `root`.
"""

from __future__ import annotations

from fnmatch import fnmatch
from pathlib import Path

import pathspec

# Directories always skipped regardless of settings (roadmap §5).
ALWAYS_SKIP = frozenset(
    {
        ".git",
        "__pycache__",
        ".venv",
        "venv",
        "node_modules",
        ".mypy_cache",
        ".pytest_cache",
        ".ruff_cache",
        ".idea",
        ".vscode",
        "dist",
        "build",
        ".DS_Store",
    }
)


def _load_gitignore(root: Path) -> pathspec.PathSpec | None:
    gi = root / ".gitignore"
    if not gi.exists():
        return None
    lines = gi.read_text(encoding="utf-8", errors="replace").splitlines()
    return pathspec.PathSpec.from_lines("gitignore", lines)


def _is_unlimited(max_depth: int) -> bool:
    # -1 (or any negative) means unlimited; 0 = root only; N = N levels.
    return max_depth < 0


def build_tree(
    root: Path,
    max_depth: int = -1,
    use_gitignore: bool = True,
    exclude: list[str] | None = None,
    include: list[str] | None = None,
) -> str:
    """Return a clean ASCII tree of `root`.

    Directories before files, alphabetically sorted within each group.
    `max_depth < 0` means unlimited; `0` shows only the root; `N` descends N
    levels.

    `exclude` adds glob patterns to skip (matched against each entry's name and
    repo-relative path). `include` force-shows entries that default skips or
    .gitignore would otherwise drop; it wins over `exclude` and applies to the
    whole subtree of a matched directory.
    """
    root = root.resolve()
    spec = _load_gitignore(root) if use_gitignore else None
    exclude = exclude or []
    include = include or []
    lines: list[str] = [root.name or str(root)]
    _walk(root, root, spec, max_depth, exclude, include,
          prefix="", depth=1, out=lines)
    return "\n".join(lines)


def _matches(name: str, rel: str, patterns: list[str]) -> bool:
    return any(fnmatch(name, p) or fnmatch(rel, p) for p in patterns)


def _included(rel: str, include: list[str]) -> bool:
    """True if `rel` matches an include pattern, or sits under a directory
    that does (so including a dir reveals its whole subtree)."""
    if not include:
        return False
    parts = rel.split("/")
    for i in range(1, len(parts) + 1):
        prefix_rel = "/".join(parts[:i])
        if _matches(parts[i - 1], prefix_rel, include):
            return True
    return False


def _skipped(
    root: Path,
    entry: Path,
    spec: pathspec.PathSpec | None,
    exclude: list[str],
    include: list[str],
) -> bool:
    rel = entry.relative_to(root).as_posix()
    # Explicit include overrides every skip rule.
    if _included(rel, include):
        return False
    if entry.name in ALWAYS_SKIP:
        return True
    if _matches(entry.name, rel, exclude):
        return True
    if spec is None:
        return False
    gi_rel = rel + "/" if entry.is_dir() else rel
    return spec.match_file(gi_rel)


def _walk(
    root: Path,
    current: Path,
    spec: pathspec.PathSpec | None,
    max_depth: int,
    exclude: list[str],
    include: list[str],
    prefix: str,
    depth: int,
    out: list[str],
) -> None:
    if not _is_unlimited(max_depth) and depth > max_depth:
        return

    try:
        entries = list(current.iterdir())
    except OSError:
        return

    entries = [e for e in entries if not _skipped(root, e, spec, exclude, include)]
    dirs = sorted((e for e in entries if e.is_dir()), key=lambda p: p.name)
    files = sorted((e for e in entries if not e.is_dir()), key=lambda p: p.name)
    ordered = dirs + files

    for i, entry in enumerate(ordered):
        last = i == len(ordered) - 1
        connector = "└── " if last else "├── "
        out.append(f"{prefix}{connector}{entry.name}")
        if entry.is_dir():
            extension = "    " if last else "│   "
            _walk(
                root,
                entry,
                spec,
                max_depth,
                exclude,
                include,
                prefix + extension,
                depth + 1,
                out,
            )
