"""Parse routine headers.

A header is a ``;--`` line followed by comment lines: the routine name, then
the fields ``In:``, ``Out:`` and ``Clobbers:``.
"""

import re
from dataclasses import dataclass, field

from asmlint.findings import ERROR, Finding
from asmlint.registers import LIST_PATTERN, parse_list
from asmlint.source import Statement

FIELDS = ("In", "Out", "Clobbers")
_FIELD = re.compile(r"\s*(In|Out|Clobbers)\s*:(.*)", re.IGNORECASE)
_CONTINUATION = re.compile(r"\s{2,}\S")
_NAME = re.compile(r"\s*([A-Za-z_.][\w.$]*)\s*")
_SIZED_LIST = rf"({LIST_PATTERN})(?:\.[bwl])?"
_ASSIGNED = re.compile(rf"(?<![\w.$(]){_SIZED_LIST}\s*=", re.IGNORECASE)
_BARE = re.compile(_SIZED_LIST, re.IGNORECASE)


@dataclass
class Field:
    """One header field: its text and the registers it names."""

    line: int
    text: str
    registers: list[str] = field(default_factory=list)


@dataclass
class Header:
    """A routine header."""

    file: str
    line: int
    name: str | None = None
    fields: dict[str, Field] = field(default_factory=dict)
    problems: list[Finding] = field(default_factory=list)

    @property
    def title(self) -> str:
        """The routine name for use in messages."""
        return self.name or "?"

    def registers(self, *names: str) -> set[str]:
        """Return the registers named in the given fields."""
        found: set[str] = set()
        for name in names:
            if name in self.fields:
                found.update(self.fields[name].registers)
        return found


def is_header_start(statement: Statement) -> bool:
    """True for the ``;--`` line that opens a header."""
    return statement.text.strip() == ";--"


def described_registers(text: str) -> list[str]:
    """Find the registers an In or Out field describes.

    A register counts when it is followed by ``=`` (``d0.w = count``) or stands
    alone between commas. Anything else, such as ``Z = found``, is prose.
    """
    registers: list[str] = []
    for match in _ASSIGNED.finditer(text):
        registers.extend(parse_list(match.group(1)) or [])
    for item in text.split(","):
        match = _BARE.fullmatch(item.strip())
        if match:
            registers.extend(parse_list(match.group(1)) or [])
    return registers


def parse_header(lines: list[Statement]) -> Header:
    """Parse a header from its ``;--`` line and the comment lines after it."""
    header = Header(lines[0].file, lines[0].line)
    current: Field | None = None
    for position, statement in enumerate(lines[1:]):
        text = statement.comment
        match = _FIELD.fullmatch(text)
        if match:
            name = match.group(1).capitalize()
            current = Field(statement.line, match.group(2).strip())
            header.fields[name] = current
        elif current and _CONTINUATION.match(text):
            current.text += " " + text.strip()
        else:
            current = None
            if position == 0 and _NAME.fullmatch(text):
                header.name = text.strip()
    _check_fields(header)
    return header


def _check_fields(header: Header) -> None:
    """Extract the registers of each field and note what is wrong with them."""

    def problem(line: int, message: str) -> None:
        header.problems.append(Finding(header.file, line, ERROR, message))

    if not header.name:
        problem(header.line, "header has no routine name")
    for name in FIELDS:
        if name not in header.fields:
            problem(header.line, f"header of {header.title} has no {name} field")
            continue
        parsed = header.fields[name]
        if not parsed.text:
            problem(
                parsed.line,
                f"the {name} field of {header.title} is empty; write - for nothing",
            )
        elif parsed.text == "-":
            continue
        elif name != "Clobbers":
            parsed.registers = described_registers(parsed.text)
        else:
            lists = [parse_list(item) for item in parsed.text.split(",")]
            if None in lists:
                problem(
                    parsed.line,
                    f"cannot parse the Clobbers field of {header.title}:"
                    f" {parsed.text!r}",
                )
            parsed.registers = [name for found in lists for name in found or []]
