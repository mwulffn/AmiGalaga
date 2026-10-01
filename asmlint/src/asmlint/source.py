"""Read assembly source into statements."""

import re
from dataclasses import dataclass

from asmlint.findings import ERROR, Finding

_LABEL_AT_START = re.compile(r"([^\s:=;]+)(::?)?")
_LABEL_INDENTED = re.compile(r"\s+([^\s:=;]+)::?")


@dataclass
class Statement:
    """One source line, split into its fields."""

    file: str
    line: int
    text: str
    label: str | None = None
    mnemonic: str | None = None  # lower case, without the size
    name: str = ""  # the mnemonic as written, without the size
    size: str | None = None
    operands: tuple[str, ...] = ()
    comment: str = ""
    # For lines that come from a macro: the macro used in the source, and a
    # number shared by every line of that one use. The line and file are
    # those of the use, not of the macro definition.
    macro: str | None = None
    expansion: int = 0
    is_macro_call: bool = False

    @property
    def is_comment(self) -> bool:
        """True for a line that holds nothing but a comment."""
        return not self.label and not self.mnemonic and bool(self.text.strip())


def words(text: str) -> set[str]:
    """Split a list of names separated by blanks into a set."""
    return set(text.split())


def problem(statement: Statement, message: str, severity: str = ERROR) -> Finding:
    """Return a finding located at a statement."""
    if statement.macro:
        message += f" (in macro {statement.macro})"
    return Finding(statement.file, statement.line, severity, message)


def is_local(label: str) -> bool:
    """True for a local label (``.name`` or ``name$``)."""
    return label.startswith(".") or label.endswith("$")


def split_comment(text: str) -> tuple[str, str]:
    """Split a line into code and the comment that follows the first ``;``."""
    if text.lstrip().startswith("*"):
        return "", text.lstrip()[1:]
    quote = ""
    for position, char in enumerate(text):
        if quote:
            if char == quote:
                quote = ""
        elif char in "'\"":
            quote = char
        elif char == ";":
            return text[:position], text[position + 1 :]
    return text, ""


def split_operands(field: str) -> tuple[str, ...]:
    """Split an operand field at the commas outside brackets and quotes.

    The field ends at the first blank, as in vasm, where the rest of the line
    is a comment. A blank straight after a comma is tolerated.
    """
    operands: list[str] = []
    current = ""
    depth = 0
    quote = ""
    angle = False
    for char in field.strip():
        if quote:
            quote = "" if char == quote else quote
        elif angle:
            angle = char != ">"
        elif char in "'\"":
            quote = char
        elif char == "<" and not current:
            angle = True
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        elif char == "," and depth == 0:
            operands.append(current)
            current = ""
            continue
        elif char.isspace():
            if current:
                break
            continue
        current += char
    if current or operands:
        operands.append(current)
    return tuple(operands)


def parse_statement(file: str, line: int, text: str) -> Statement:
    """Split one source line into label, mnemonic, size, operands and comment."""
    code, comment = split_comment(text)
    statement = Statement(file, line, text, comment=comment)
    match = _LABEL_AT_START.match(code) or _LABEL_INDENTED.match(code)
    if match:
        statement.label = match.group(1)
        code = code[match.end() :]
    code = code.strip()
    if not code:
        return statement
    if code.startswith("="):
        name, field = "=", code[1:]
    else:
        name = code.split()[0]
        field = code[len(name) :]
    name, _, size = name.partition(".")
    statement.name = name
    statement.mnemonic = name.lower()
    statement.size = size.lower() or None
    statement.operands = split_operands(field)
    return statement
