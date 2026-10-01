"""Follow a routine's code and track which registers hold their entry value.

The analysis walks every path through the routine. Along the way it keeps a
``State``: the set of registers whose value may differ from the one they had on
entry (the dirty registers), and a model of what the routine has pushed on the
stack. A register saved with a long push while it is still clean and popped
back later is clean again, which is how saved and restored registers count as
preserved.
"""

import re
from dataclasses import dataclass, field

from asmlint.m68k import destinations, written_registers
from asmlint.registers import STACK, canonical, parse_list
from asmlint.source import Statement

# A stack slot is (size in bytes, what it holds). It holds either the entry
# value of the named register, or None for anything else. A slot of size 0
# marks the frame that ``link`` set up for the named register. A size that is
# not a plain number is kept as text (``FRAME``): such a slot can only be
# released by exactly the same expression.
Size = int | str
Slot = tuple[Size, str | None]
Stack = tuple[Slot, ...] | None  # None: the stack depth is unknown

RETURNS = {"rts": "rts", "rtr": "rts", "rte": "rte"}
_PUSH = re.compile(r"-\(\s*(sp|a7)\s*\)", re.IGNORECASE)
_POP = re.compile(r"\(\s*(sp|a7)\s*\)\+", re.IGNORECASE)
_VIA_STACK = re.compile(r"\((.*,)?\s*(sp|a7)\s*[,)]", re.IGNORECASE)
_AMOUNT = r"(-?)([\w$*/+]+)"
_STACK_OFFSET = re.compile(
    rf"{_AMOUNT}\((?:sp|a7)\)|\({_AMOUNT},(?:sp|a7)\)", re.IGNORECASE
)
_IMMEDIATE = re.compile(rf"#{_AMOUNT}")
_NAME = r"\.?[A-Za-z_]\w*\$?"
_TARGET = re.compile(
    rf"({_NAME})(?:\.[wl])?(?:\(pc\))?|\(({_NAME}),pc\)", re.IGNORECASE
)


@dataclass(frozen=True)
class State:
    """What is known at one point in a routine.

    ``dirty`` holds a (register, node index) pair for every instruction that
    may have changed a register which has not been restored since.
    """

    dirty: frozenset[tuple[str, int]] = frozenset()
    stack: Stack = ()

    @property
    def registers(self) -> set[str]:
        """The registers that may not hold their entry value."""
        return {register for register, _ in self.dirty}


@dataclass(frozen=True)
class Call:
    """A call or jump to other code, and the registers that code changes.

    A tail call leaves the routine: its effect counts where the routine ends,
    not on the instructions that follow.
    """

    via: str  # for messages: "the call to Foo"
    registers: frozenset[str] | set[str]
    tail: bool = False


@dataclass
class Node:
    """One instruction in a routine, with where execution goes next."""

    statement: Statement
    index: int = 0
    successors: list[int] = field(default_factory=list)
    # How the routine ends here: "rts", "rte", or "tail" for a jump elsewhere.
    exit: str | None = None
    # "code" for an instruction, "data" for a data directive, and for
    # conditional assembly "fork" (if) and "skip" (else). A fork goes on to the
    # next node when its condition holds and to ``jumps`` when it does not; a
    # skip, at the end of a branch, goes to ``jumps``, past the endc.
    kind: str = "code"
    jumps: list[int] = field(default_factory=list)
    condition: str = ""  # what a fork tests
    negated: bool = False  # the fork tests for the opposite of ``condition``
    scope: str = ""  # the global label that local labels here belong to
    annotations: dict = field(default_factory=dict)
    calls: list[Call] = field(default_factory=list)
    falls_off: bool = False  # execution runs past the end of the file
    errors: list[str] = field(default_factory=list)  # why it cannot be analysed

    @property
    def is_data(self) -> bool:
        """True for a data directive."""
        return self.kind == "data"


def direct_target(operand: str) -> str | None:
    """Return the label a branch, jump or call goes to, or None if indirect."""
    match = _TARGET.fullmatch(operand)
    return match.group(1) or match.group(2) if match else None


def join(first: State | None, second: State) -> State:
    """Combine the states of two paths that meet."""
    if first is None or first == second:
        return second
    stack: Stack = None
    if first.stack is not None and second.stack is not None:
        sizes = [size for size, _ in first.stack]
        if sizes == [size for size, _ in second.stack]:
            stack = tuple(
                a if a == b else (a[0], None)
                for a, b in zip(first.stack, second.stack, strict=True)
            )
    return State(first.dirty | second.dirty, stack)


def push(stack: Stack, size: Size, holds: str | None = None) -> Stack:
    """Push a slot."""
    if stack is None or size == 0 and holds is None:
        return stack
    return (*stack, (size, holds))


def pop(stack: Stack, size: Size) -> tuple[Stack, str | None]:
    """Pop ``size`` bytes; return the new stack and what the popped slot held.

    Popping more than the routine pushed makes the stack unknown, and so does
    a size given as an expression that does not match the slot on top.
    """
    slots = list(stack or ())
    while slots and slots[-1][0] == 0:
        slots.pop()
    if slots and slots[-1][0] == size:
        return tuple(slots[:-1]), slots[-1][1]
    if stack is None or isinstance(size, str):
        return None, None
    while size > 0 and slots:
        top = slots.pop()[0]
        if isinstance(top, str):
            return None, None
        if top > size:
            slots.append((top - size, None))
        size -= min(top, size)
    return (None if size > 0 else tuple(slots)), None


def amount(text: str) -> Size:
    """Turn the text of a stack size into a number where it is one."""
    if text.isdigit():
        return int(text)
    if re.fullmatch(r"\$[0-9a-fA-F]+", text):
        return int(text[1:], 16)
    return text


def step(state: State, node: Node) -> State:
    """Return the state after executing one instruction."""
    if node.kind != "code":
        return state
    before = state.registers
    dirty, stack = _execute(node.statement, set(before), state.stack)
    for call in node.calls:
        if not call.tail:
            dirty |= call.registers - {STACK}
            stack = None if STACK in call.registers else stack
    marks = {(register, index) for register, index in state.dirty if register in dirty}
    marks |= {(register, node.index) for register in dirty - before}
    return State(frozenset(marks), stack)


def _execute(statement: Statement, dirty: set[str], stack: Stack) -> tuple[set, Stack]:
    """Apply one instruction to the set of dirty registers and the stack."""
    mnemonic, operands = statement.mnemonic, statement.operands
    long = statement.size == "l"
    width = 4 if long else 2
    source, target = (operands[0], operands[-1]) if operands else ("", "")
    saved = restored = None
    if mnemonic in ("move", "movea") and STACK not in map(canonical, operands):
        saved, restored = canonical(source), canonical(target)
    if mnemonic == "movem":
        pushed = parse_list(source) if _PUSH.fullmatch(target) else None
        popped = parse_list(target) if _POP.fullmatch(source) else None
        for register in reversed(pushed or []):
            clean = long and register not in dirty
            stack = push(stack, width, register if clean else None)
        for register in popped or []:
            stack, held = pop(stack, width)
            if register == STACK:
                stack = None
                continue
            dirty.add(register)
            if long and held == register:
                dirty.discard(register)
        if pushed is not None or popped is not None:
            return dirty, stack
    if saved and long and _PUSH.fullmatch(target):
        stack = push(stack, 4, None if saved in dirty else saved)
    elif restored and long and _POP.fullmatch(source):
        stack, held = pop(stack, 4)
        dirty.add(restored)
        if held == restored:
            dirty.discard(restored)
    elif mnemonic == "link":
        stack = _link(stack, dirty, operands)
    elif mnemonic == "unlk":
        stack = _unlink(stack, dirty, canonical(source))
    else:
        if mnemonic == "pea":
            stack = push(stack, 4)
        for operand in operands:
            if _PUSH.fullmatch(operand):
                stack = push(stack, width)
            elif _POP.fullmatch(operand):
                stack, _ = pop(stack, width)
        written = written_registers(statement)
        if STACK in written:
            stack = _adjust(stack, mnemonic, operands)
        if stack and any(map(_writes_into_stack, destinations(statement))):
            stack = tuple((size, None if size else held) for size, held in stack)
        if stack and any((0, register) in stack for register in written):
            stack = None
        dirty |= written - {STACK}
    return dirty, stack


def _writes_into_stack(operand: str) -> bool:
    """True for a memory operand addressed through the stack pointer.

    Writing there may overwrite a saved register. A push does not.
    """
    return bool(_VIA_STACK.search(operand)) and not _PUSH.fullmatch(operand)


def _link(stack: Stack, dirty: set[str], operands: tuple[str, ...]) -> Stack:
    """Model ``link an,#-size``: save an, mark the frame, reserve the space."""
    register = canonical(operands[0]) if operands else None
    if register is None:
        return None
    size = _IMMEDIATE.fullmatch(operands[-1])
    stack = push(stack, 4, None if register in dirty else register)
    stack = push(stack, 0, register)
    dirty.add(register)
    if not size or (size.group(1) != "-" and size.group(2) != "0"):
        return None
    return push(stack, amount(size.group(2)))


def _unlink(stack: Stack, dirty: set[str], register: str | None) -> Stack:
    """Model ``unlk an``: drop the frame and restore an."""
    if register is None:
        return None
    dirty.add(register)
    if stack is None or (0, register) not in stack:
        return None
    stack = stack[: stack.index((0, register))]
    stack, held = pop(stack, 4)
    if held == register:
        dirty.discard(register)
    return stack


def _adjust(stack: Stack, mnemonic: str | None, operands: tuple[str, ...]) -> Stack:
    """Model arithmetic on the stack pointer; anything else makes it unknown."""
    immediate = _IMMEDIATE.fullmatch(operands[0])
    offset = _STACK_OFFSET.fullmatch(operands[0])
    if immediate and mnemonic in ("addq", "adda", "addi", "add"):
        sign, size = immediate.groups()
        release = sign != "-"
    elif immediate and mnemonic in ("subq", "suba", "subi", "sub"):
        sign, size = immediate.groups()
        release = sign == "-"
    elif offset and mnemonic == "lea":
        sign, size = offset.group(1, 2) if offset.group(2) else offset.group(3, 4)
        release = sign != "-"
    else:
        return None
    return pop(stack, amount(size))[0] if release else push(stack, amount(size))


def successors(node: Node, choices: dict[str, bool]) -> list[int]:
    """Return where execution goes after a node.

    ``choices`` says which conditions of conditional assembly hold; a fork
    whose condition is not in it goes both ways.
    """
    if node.kind != "fork" or node.condition not in choices:
        return node.successors
    holds = choices[node.condition] != node.negated
    wanted = [node.index + 1] if holds else node.jumps
    return [index for index in node.successors if index in wanted]


def analyse(
    nodes: list[Node], choices: dict[str, bool] | None = None
) -> list[State | None]:
    """Return the state before each node, or None for nodes never reached."""
    states: list[State | None] = [None] * len(nodes)
    if not nodes:
        return states
    states[0] = State()
    pending = [0]
    while pending:
        index = pending.pop()
        after = step(states[index], nodes[index])
        for successor in successors(nodes[index], choices or {}):
            merged = join(states[successor], after)
            if merged != states[successor]:
                states[successor] = merged
                pending.append(successor)
    return states
