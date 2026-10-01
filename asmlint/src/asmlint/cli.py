"""The ``asmlint`` command."""

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path

from asmlint.findings import ERROR
from asmlint.linter import DEFAULT_RESERVED, lint_files
from asmlint.registers import canonical


def parse_arguments(arguments: Sequence[str] | None) -> argparse.Namespace:
    """Parse the command line."""
    parser = argparse.ArgumentParser(
        prog="asmlint",
        description=(
            "Check the routine headers of 68000 assembly source (vasm, Motorola"
            " syntax) against what the code does to registers."
        ),
    )
    parser.add_argument("files", nargs="+", type=Path, metavar="FILE")
    parser.add_argument(
        "-I",
        "--include-dir",
        action="append",
        default=[],
        type=Path,
        metavar="DIR",
        help="directory to search for include files (may be repeated)",
    )
    parser.add_argument(
        "--reserved",
        default=",".join(DEFAULT_RESERVED),
        metavar="REGISTERS",
        help=(
            "registers that may not be written without a lint: allow annotation,"
            " separated by commas; - for none (default: %(default)s)"
        ),
    )
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    """Run the linter; return 1 if it found errors and 2 if it could not run."""
    options = parse_arguments(arguments)
    names = [] if options.reserved == "-" else options.reserved.split(",")
    reserved = [canonical(name) for name in names]
    if None in reserved:
        wrong = names[reserved.index(None)]
        print(f"asmlint: {wrong} is not a register", file=sys.stderr)
        return 2
    try:
        findings = lint_files(options.files, reserved, options.include_dir)
    except OSError as error:
        print(f"asmlint: {error}", file=sys.stderr)
        return 2
    for finding in findings:
        print(finding)
    return 1 if any(finding.severity == ERROR for finding in findings) else 0
