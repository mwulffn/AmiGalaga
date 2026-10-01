"""Check 68000 assembly routine headers against what the code does to registers."""

from asmlint.findings import ERROR, WARNING, Finding
from asmlint.linter import lint_files

__all__ = ["ERROR", "WARNING", "Finding", "lint_files"]
