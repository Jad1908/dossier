"""Repo walker: builds an ASCII tree honoring default skips and .gitignore.

Side-effect-free except for reading the filesystem under `root`.
"""

from __future__ import annotations

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
    # Schema default 0 means unlimited; -1 is also accepted as unlimited.
    return max_depth <= 0


def build_tree(
    root: Path,
    max_depth: int = 0,
    use_gitignore: bool = True,
) -> str:
    """Return a clean ASCII tree of `root`.

    Directories before files, alphabetically sorted within each group.
    `max_depth <= 0` means unlimited.
    """
    root = root.resolve()
    spec = _load_gitignore(root) if use_gitignore else None
    lines: list[str] = [root.name or str(root)]
    _walk(root, root, spec, max_depth, prefix="", depth=1, out=lines)
    return "\n".join(lines)


def _skipped(root: Path, entry: Path, spec: pathspec.PathSpec | None) -> bool:
    if entry.name in ALWAYS_SKIP:
        return True
    if spec is None:
        return False
    rel = entry.relative_to(root).as_posix()
    if entry.is_dir():
        rel += "/"
    return spec.match_file(rel)


def _walk(
    root: Path,
    current: Path,
    spec: pathspec.PathSpec | None,
    max_depth: int,
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

    entries = [e for e in entries if not _skipped(root, e, spec)]
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
                prefix + extension,
                depth + 1,
                out,
            )
