"""Shared fixtures: lint inline assembly snippets written to a temporary directory."""

from collections.abc import Callable
from pathlib import Path

import pytest

from asmlint import lint_files

Lint = Callable[..., list[str]]


@pytest.fixture
def lint(tmp_path: Path) -> Lint:
    """Return a function that lints assembly text and returns the findings as text.

    The positional argument is the text of ``main.s``. Keyword arguments name
    further files (``other_s="..."`` becomes ``other.s``); files ending in ``.s``
    are linted, the rest (``.i``) are only there to be included. Options for
    ``lint_files`` are passed in ``options``.
    """

    def run(main: str, options: dict | None = None, **others: str) -> list[str]:
        sources = {"main.s": main}
        for key, text in others.items():
            stem, _, suffix = key.rpartition("_")
            sources[f"{stem}.{suffix}"] = text
        paths = []
        for name, text in sources.items():
            path = tmp_path / name
            path.write_text(text)
            if name.endswith(".s"):
                paths.append(path)
        findings = lint_files(paths, **(options or {}))
        prefix = f"{tmp_path}/"
        return [str(finding).removeprefix(prefix) for finding in findings]

    return run
