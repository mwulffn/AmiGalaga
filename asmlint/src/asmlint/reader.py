"""Read a source file with its include files and expand its macros.

The result is one flat list of statements, as the assembler would see them,
except that conditional assembly is left in: the linter checks every branch.
"""

import re
from collections.abc import Iterable
from pathlib import Path

from asmlint.findings import ERROR, Finding
from asmlint.source import Statement, parse_statement, problem, split_comment

MAX_DEPTH = 50
_ESCAPE = re.compile(r"\\([@#0-9])")


class Reader:
    """Reads one source file given on the command line and all it includes."""

    def __init__(self, include_dirs: Iterable[Path] = ()) -> None:
        self.statements: list[Statement] = []
        self.findings: list[Finding] = []
        self.include_dirs = [Path(directory) for directory in include_dirs]
        self.macros: dict[str, list[str]] = {}
        # Names defined with equr or reg, and the register (list) they stand for.
        self.aliases: dict[str, str] = {}
        self.alias_pattern: re.Pattern | None = None
        self.files_read: set[Path] = set()
        self.expansions = 0

    def read_file(self, path: Path) -> None:
        """Read a file, unless it has been read already."""
        if path.resolve() in self.files_read:
            return
        self.files_read.add(path.resolve())
        lines = iter(enumerate(path.read_text(errors="replace").splitlines(), 1))
        for number, text in lines:
            statement = parse_statement(str(path), number, text)
            if statement.mnemonic == "end":
                break
            if statement.mnemonic == "rem":
                self._skip(lines, "erem", statement, "rem has no erem")
            elif statement.mnemonic == "macro":
                name = statement.label or "".join(statement.operands[:1])
                missing = f"macro {name} has no endm"
                self.macros[name] = self._skip(lines, "endm", statement, missing)
            else:
                self._add(statement, path.parent)

    def _skip(
        self,
        lines: Iterable[tuple[int, str]],
        last: str,
        start: Statement,
        missing: str,
    ) -> list[str]:
        """Consume lines up to the one with the given directive; return them.

        Reports ``missing`` at the starting statement if the file ends first.
        """
        skipped: list[str] = []
        for number, text in lines:
            if parse_statement("", number, text).mnemonic == last:
                return skipped
            skipped.append(text)
        self.findings.append(problem(start, missing))
        return skipped

    def _add(self, statement: Statement, directory: Path, depth: int = 0) -> None:
        """Add a statement, following an include or expanding a macro."""
        mnemonic, operands = statement.mnemonic, statement.operands
        if statement.name in self.macros:
            self._expand(statement, directory, depth)
            return
        self.statements.append(statement)
        if mnemonic == "include" and operands:
            self._include(statement, directory)
        elif mnemonic == "incdir" and operands:
            self.include_dirs.append(directory / operands[0].strip("\"'"))
        elif mnemonic in ("equr", "reg") and statement.label and operands:
            self.aliases[statement.label] = operands[0]
            names = "|".join(map(re.escape, self.aliases))
            self.alias_pattern = re.compile(rf"(?<![\w.$])({names})(?![\w$])")
        elif self.alias_pattern:
            pattern = self.alias_pattern
            statement.operands = tuple(
                pattern.sub(lambda match: self.aliases[match.group(1)], operand)
                for operand in operands
            )

    def _include(self, statement: Statement, directory: Path) -> None:
        """Read an include file, looking next to the including file first."""
        name = statement.operands[0].strip("\"'")
        for candidate in [directory, Path(), *self.include_dirs]:
            if (candidate / name).is_file():
                self.read_file(candidate / name)
                return
        self.findings.append(
            problem(statement, f"cannot find the include file {name!r}")
        )

    def _expand(self, call: Statement, directory: Path, depth: int) -> None:
        """Replace a macro call by the macro's lines with the arguments filled in."""
        if depth > MAX_DEPTH:
            message = (
                f"macro {call.name} is expanded more than {MAX_DEPTH} levels deep;"
                " recursive macros are not supported"
            )
            self.findings.append(Finding(call.file, call.line, ERROR, message))
            return
        self.expansions += 1
        unique = f"_{self.expansions:06d}"
        if not call.expansion:
            call.macro = call.name
            call.expansion = self.expansions
        call.is_macro_call = True
        self.statements.append(call)
        arguments = [
            argument[1:-1] if argument[:1] == "<" else argument
            for argument in call.operands
        ]

        def fill(match: re.Match) -> str:
            key = match.group(1)
            if key == "@":
                return unique
            if key == "#":
                return str(len(arguments))
            if key == "0":
                return call.size or "w"
            return arguments[int(key) - 1] if int(key) <= len(arguments) else ""

        for text in self.macros[call.name]:
            line = parse_statement(call.file, call.line, _ESCAPE.sub(fill, text))
            line.macro = call.macro
            line.expansion = call.expansion
            unknown = re.search(r"\\.", split_comment(line.text)[0])
            if unknown:
                message = f"cannot expand '{unknown.group()}' in macro {call.name}"
                self.findings.append(Finding(call.file, call.line, ERROR, message))
            self._add(line, directory, depth + 1)


def read_source(
    path: Path, include_dirs: Iterable[Path] = ()
) -> tuple[list[Statement], list[Finding]]:
    """Read a source file into statements; also return what went wrong."""
    reader = Reader(include_dirs)
    reader.read_file(Path(path))
    return reader.statements, reader.findings
