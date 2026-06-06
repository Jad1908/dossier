from pathlib import Path

from dossier.tree import build_tree


def test_default_skips_and_gitignore(sample_repo: Path):
    out = build_tree(sample_repo, use_gitignore=True)
    # Always-skipped directory.
    assert "__pycache__" not in out
    # Gitignored entries.
    assert "ignored_by_git" not in out
    assert "debug.log" not in out
    # Real content present.
    assert "src" in out
    assert "app.py" in out
    assert "README.md" in out


def test_gitignore_disabled_includes_ignored(sample_repo: Path):
    out = build_tree(sample_repo, use_gitignore=False)
    assert "ignored_by_git" in out
    assert "debug.log" in out
    # Always-skip still applies regardless.
    assert "__pycache__" not in out


def test_max_depth_limits_descent(sample_repo: Path):
    out = build_tree(sample_repo, max_depth=1, use_gitignore=True)
    assert "src" in out
    # Files one level under src should be hidden at depth 1.
    assert "app.py" not in out


def test_max_depth_negative_is_unlimited(sample_repo: Path):
    out = build_tree(sample_repo, max_depth=-1, use_gitignore=True)
    assert "src" in out
    assert "app.py" in out  # descends fully


def test_max_depth_zero_shows_root_only(sample_repo: Path):
    out = build_tree(sample_repo, max_depth=0, use_gitignore=True)
    assert out.splitlines() == [sample_repo.name]  # nothing below root


def test_dirs_before_files_and_sorted(sample_repo: Path):
    out = build_tree(sample_repo, use_gitignore=True)
    lines = out.splitlines()
    # First line is the root name.
    assert lines[0] == sample_repo.name
    # 'src' (dir) must appear before 'README.md' (file) at top level.
    top = [ln for ln in lines if "── " in ln and "│" not in ln.split("── ")[0]]
    names = [ln.split("── ")[-1] for ln in top]
    assert names.index("src") < names.index("README.md")


def test_exclude_removes_dir(sample_repo: Path):
    out = build_tree(sample_repo, exclude=["src"])
    assert "src" not in out
    assert "app.py" not in out
    assert "README.md" in out  # untouched


def test_exclude_glob(sample_repo: Path):
    out = build_tree(sample_repo, use_gitignore=False, exclude=["*.log"])
    assert "debug.log" not in out


def test_include_overrides_gitignore(sample_repo: Path):
    out = build_tree(sample_repo, use_gitignore=True, include=["ignored_by_git"])
    assert "ignored_by_git" in out
    assert "secret.txt" in out  # subtree revealed too


def test_include_overrides_always_skip(sample_repo: Path):
    out = build_tree(sample_repo, include=["__pycache__"])
    assert "__pycache__" in out


def test_deterministic(sample_repo: Path):
    assert build_tree(sample_repo) == build_tree(sample_repo)


def test_uses_ascii_connectors(sample_repo: Path):
    out = build_tree(sample_repo)
    assert "├──" in out or "└──" in out
