"""Find the routines in a source file and check how their headers are placed."""

from dataclasses import dataclass, field

from asmlint.annotations import parse_annotation
from asmlint.findings import ERROR, Finding
from asmlint.header import Header, is_header_start, parse_header
from asmlint.m68k import is_instruction
from asmlint.source import Statement, is_local


@dataclass
class Routine:
    """A routine: its header and the statements up to the next header."""

    header: Header
    body: list[Statement] = field(default_factory=list)
    # Reserved registers the header's annotations allow the routine to write.
    allowed: set[str] = field(default_factory=set)
    problems: list[Finding] = field(default_factory=list)

    @property
    def declared(self) -> set[str]:
        """The registers the header says the routine changes."""
        return self.header.registers("Out", "Clobbers")


def find_routines(
    statements: list[Statement],
) -> tuple[list[Routine], list[Statement]]:
    """Split a file into routines, one per header.

    Also returns the statements that come before the first header.
    """
    routines: list[Routine] = []
    orphans: list[Statement] = []
    position = 0
    while position < len(statements):
        statement = statements[position]
        if is_header_start(statement):
            end = position + 1
            while end < len(statements) and statements[end].is_comment:
                end += 1
            routine = Routine(parse_header(statements[position:end]))
            _read_header_annotations(routine, statements[position:end])
            routines.append(routine)
            position = end
            continue
        (routines[-1].body if routines else orphans).append(statement)
        position += 1
    return routines, orphans


def _read_header_annotations(routine: Routine, lines: list[Statement]) -> None:
    """Apply the lint annotations written in a routine's header."""
    for statement in lines:
        annotation = parse_annotation(statement)
        if isinstance(annotation, Finding):
            routine.problems.append(annotation)
        elif annotation and annotation.keyword == "allow":
            routine.allowed |= annotation.registers
        elif annotation:
            message = (
                f"the lint annotation {annotation.keyword!r} cannot be used in a header"
            )
            routine.problems.append(
                Finding(statement.file, statement.line, ERROR, message)
            )


def check_orphans(orphans: list[Statement]) -> list[Finding]:
    """Report code that comes before the first header of a file."""
    findings = []
    label: Statement | None = None
    for statement in orphans:
        if statement.label and not is_local(statement.label):
            label = statement
        if not is_instruction(statement.mnemonic):
            continue
        if label:
            message = f"{label.label} has code but no routine header"
            findings.append(Finding(label.file, label.line, ERROR, message))
        else:
            message = "code outside a routine: no routine header"
            findings.append(Finding(statement.file, statement.line, ERROR, message))
    return findings


def check_label(routine: Routine) -> list[Finding]:
    """Check that the header is followed by the label it names."""
    header = routine.header
    line = header.line
    for statement in routine.body:
        line = statement.line
        if statement.label and not is_local(statement.label):
            if not header.name or statement.label == header.name:
                return []
            message = (
                f"header names {header.name} but the label that follows is"
                f" {statement.label}"
            )
            return [Finding(header.file, line, ERROR, message)]
        if statement.label or is_instruction(statement.mnemonic):
            break
    message = f"header of {header.title} is not followed by a label"
    return [Finding(header.file, line, ERROR, message)]
