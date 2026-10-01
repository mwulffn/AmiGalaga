"""Register names and register lists."""

import re

DATA = tuple(f"d{n}" for n in range(8))
ADDRESS = tuple(f"a{n}" for n in range(8))
REGISTERS = DATA + ADDRESS
STACK = "a7"

REGISTER_PATTERN = r"(?:[da][0-7]|sp)"
LIST_PATTERN = rf"{REGISTER_PATTERN}(?:\s*[-/]\s*{REGISTER_PATTERN})*"
_LIST = re.compile(LIST_PATTERN, re.IGNORECASE)


def canonical(name: str) -> str | None:
    """Return the register a name stands for (``SP`` is ``a7``), or None."""
    name = name.strip().lower()
    if name == "sp":
        return STACK
    return name if name in REGISTERS else None


def parse_list(text: str) -> list[str] | None:
    """Parse a register list such as ``d0-d2/a0`` into register names, in order.

    Returns None when the text is not a register list.
    """
    text = text.strip()
    if not _LIST.fullmatch(text):
        return None
    found: set[str] = set()
    for part in text.split("/"):
        ends = [REGISTERS.index(canonical(name) or "") for name in part.split("-")]
        if sorted(ends) != ends:
            return None
        found.update(REGISTERS[ends[0] : ends[-1] + 1])
    return [register for register in REGISTERS if register in found]
