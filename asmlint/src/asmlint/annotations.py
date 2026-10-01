"""Lint annotations: ``; lint: keyword arguments`` comments.

``clobbers``  the registers changed by the call or jump on that line
``targets``   the labels an indirect call or jump may go to
``allow``     reserved registers that may be written
"""

import re
from dataclasses import dataclass

from asmlint.findings import ERROR, Finding
from asmlint.registers import parse_list
from asmlint.source import Statement

KEYWORDS = ("clobbers", "targets", "allow")
_ANNOTATION = re.compile(r"\blint:\s*(\S+)\s*(.*)", re.IGNORECASE)
_LABEL = re.compile(r"\.?[A-Za-z_]\w*\$?")


@dataclass
class Annotation:
    """One annotation, with its arguments parsed."""

    keyword: str
    registers: set[str]
    labels: list[str]


def parse_annotation(statement: Statement) -> Annotation | Finding | None:
    """Parse the annotation in a statement's comment, if it has one."""
    match = _ANNOTATION.search(statement.comment)
    if not match:
        return None
    keyword, argument = match.group(1).lower(), match.group(2).strip()
    items = [item.strip() for item in argument.split(",")]
    annotation = Annotation(keyword, set(), [])
    if keyword not in KEYWORDS:
        message = f"unknown lint annotation {match.group(1)!r}"
    elif keyword == "targets" and all(_LABEL.fullmatch(item) for item in items):
        annotation.labels = items
        return annotation
    elif keyword != "targets" and (argument == "-" or all(map(parse_list, items))):
        for item in items:
            annotation.registers.update(parse_list(item) or [])
        return annotation
    else:
        message = f"cannot parse the lint annotation {keyword + ' ' + argument!r}"
    return Finding(statement.file, statement.line, ERROR, message)
