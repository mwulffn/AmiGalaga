"""Build the control-flow graph of a routine."""

from collections.abc import Callable
from dataclasses import dataclass, field

from asmlint.annotations import Annotation, parse_annotation
from asmlint.directives import (
    ELSE,
    ELSE_IF,
    END_IF,
    IF,
    condition,
    is_data,
    is_ignored,
)
from asmlint.findings import Finding
from asmlint.flow import RETURNS, Call, Node, direct_target
from asmlint.m68k import BRANCHES, LOOPS, is_instruction
from asmlint.registers import parse_list
from asmlint.routines import Routine
from asmlint.source import Statement, is_local

# Looks up a routine by name: returns the registers it declares as changed, or
# the reason it cannot be found.
Resolver = Callable[[str], set[str] | str]
ANNOTATE = "add a lint: clobbers or lint: targets annotation"


@dataclass
class Graph:
    """The nodes of a routine and what was found while linking them."""

    nodes: list[Node] = field(default_factory=list)
    labels: dict[str, int] = field(default_factory=dict)
    # Global labels inside the routine, by the node they point at.
    entries: dict[int, Statement] = field(default_factory=dict)
    problems: list[Finding] = field(default_factory=list)


def build_graph(
    routine: Routine, following: Routine | None, resolve: Resolver
) -> Graph:
    """Turn the code of a routine into nodes linked by control flow.

    ``following`` is the routine that comes next in the source, which execution
    falls into when it runs past the end of this one.
    """
    collector = _Collector()
    for statement in routine.body:
        collector.add(statement)
    collector.finish()
    graph = collector.graph
    for node in graph.nodes:
        _link(node, graph, routine, following, resolve)
    return graph


class _Collector:
    """Creates the nodes of a routine and records its labels and annotations."""

    def __init__(self) -> None:
        self.graph = Graph()
        self.scope = ""  # the last global label
        # Annotations waiting for the next instruction.
        self.pending: dict[str, Annotation] = {}
        # Annotations given on a macro call, which apply to every instruction
        # of that expansion: the expansion's number and the annotations.
        self.spread: tuple[int, dict[str, Annotation]] = (0, {})
        # Open conditionals: the fork that still has to learn where to go when
        # its condition fails (None after an else), and the skips so far.
        self.conditionals: list[tuple[Node | None, list[Node]]] = []

    def add(self, statement: Statement) -> None:
        """Take in the next statement of the routine."""
        self._read_annotation(statement)
        self._read_label(statement)
        mnemonic = statement.mnemonic
        if mnemonic is None or statement.is_macro_call or is_ignored(statement):
            return
        if mnemonic in IF | ELSE | ELSE_IF | END_IF:
            self._conditional(statement)
        elif is_data(statement):
            self._node(statement, "data")
        else:
            node = self._node(statement, "code")
            if statement.expansion and statement.expansion == self.spread[0]:
                node.annotations.update(self.spread[1])
            node.annotations.update(self.pending)
            self.pending = {}
            if not is_instruction(mnemonic):
                node.errors.append(
                    f"unknown instruction, directive or macro {statement.name!r}"
                )

    def finish(self) -> None:
        """Close the conditionals that the routine leaves open."""
        for waiting, skips in self.conditionals:
            self._close(waiting, skips)

    def _node(self, statement: Statement, kind: str) -> Node:
        nodes = self.graph.nodes
        nodes.append(Node(statement, len(nodes), kind=kind, scope=self.scope))
        return nodes[-1]

    def _read_annotation(self, statement: Statement) -> None:
        annotation = parse_annotation(statement)
        if isinstance(annotation, Finding):
            self.graph.problems.append(annotation)
        elif annotation:
            self.pending[annotation.keyword] = annotation
        if statement.is_macro_call and self.pending:
            self.spread = (statement.expansion, self.pending)
            self.pending = {}

    def _read_label(self, statement: Statement) -> None:
        index = len(self.graph.nodes)
        if statement.label and is_local(statement.label):
            self.graph.labels[self.scope + statement.label] = index
        elif statement.label:
            self.scope = statement.label
            self.graph.labels[self.scope] = index
            self.graph.entries.setdefault(index, statement)

    def _conditional(self, statement: Statement) -> None:
        """Turn conditional assembly into forks and skips.

        A conditional that is not opened inside the routine is ignored.
        """
        mnemonic = statement.mnemonic
        if mnemonic in IF:
            self.conditionals.append((self._fork(statement), []))
        elif not self.conditionals:
            return
        elif mnemonic in END_IF:
            self._close(*self.conditionals.pop())
        else:
            waiting, skips = self.conditionals.pop()
            skips.append(self._node(statement, "skip"))
            if waiting:
                waiting.jumps.append(len(self.graph.nodes))
            waiting = self._fork(statement) if mnemonic in ELSE_IF else None
            self.conditionals.append((waiting, skips))

    def _fork(self, statement: Statement) -> Node:
        node = self._node(statement, "fork")
        node.condition, node.negated = condition(statement)
        return node

    def _close(self, waiting: Node | None, skips: list[Node]) -> None:
        """Send the ends of the branches of a conditional to what follows it."""
        for node in [*skips, waiting]:
            if node:
                node.jumps.append(len(self.graph.nodes))


def _link(
    node: Node,
    graph: Graph,
    routine: Routine,
    following: Routine | None,
    resolve: Resolver,
) -> None:
    """Work out where execution goes after a node and what a call there changes."""
    title = routine.header.title
    mnemonic = node.statement.mnemonic or ""
    operands = node.statement.operands
    text = f"{mnemonic} {','.join(operands)}"
    name = direct_target(operands[-1]) if operands else None
    clobbers = node.annotations.get("clobbers")
    targets = node.annotations.get("targets")

    def follow(index: int) -> None:
        if index < len(graph.nodes):
            node.successors.append(index)
        elif following:
            via = f"falling through into {following.header.title}"
            node.calls.append(Call(via, following.declared, tail=True))
            node.exit = node.exit or "tail"
        else:
            node.falls_off = True

    def key(target: str) -> str:
        return node.scope + target if is_local(target) else target

    def leave(via: str, registers: set[str], kind: str) -> None:
        """Record a call, or a jump out of the routine, that changes registers."""
        node.calls.append(Call(via, registers, tail=kind == "jump"))
        if kind == "jump":
            node.exit = "tail"

    def go_to(target: str, kind: str) -> None:
        """Call or jump to a label: one in this routine or another routine."""
        if kind == "jump" and key(target) in graph.labels:
            follow(graph.labels[key(target)])
            return
        if kind == "jump" and is_local(target):
            node.errors.append(
                f"cannot find the label {target} that {title} branches to"
            )
            return
        found = resolve(target)
        if isinstance(found, str):
            node.errors.append(f"cannot analyse the {kind} to {target}: {found}")
        else:
            leave(f"the {kind} to {target}", found, kind)

    def transfer(kind: str) -> None:
        """Handle a call or jump, using the annotations where they are needed."""
        if name and kind == "jump" and key(name) in graph.labels:
            go_to(name, kind)
        elif clobbers and name:
            leave(f"the {kind} to {name}", clobbers.registers, kind)
        elif clobbers:
            leave(f"the indirect {kind} {text}", clobbers.registers, kind)
        elif name:
            go_to(name, kind)
        elif targets:
            for target in targets.labels:
                go_to(target, kind)
        else:
            node.errors.append(f"cannot analyse the indirect {kind} {text}; {ANNOTATE}")

    node.exit = RETURNS.get(mnemonic)
    if node.exit or node.is_data:
        return
    if node.kind in ("fork", "skip"):
        if node.kind == "fork":
            follow(node.index + 1)
        for index in node.jumps:
            follow(index)
        return
    if mnemonic in ("bra", "jmp"):
        transfer("jump")
        return
    if mnemonic in ("bsr", "jsr"):
        transfer("call")
    elif mnemonic == "trap" and clobbers:
        leave(f"the {text}", clobbers.registers, "call")
    elif mnemonic == "trap":
        node.errors.append(f"cannot analyse {text}; add a lint: clobbers annotation")
    elif mnemonic in BRANCHES or mnemonic in LOOPS:
        transfer("jump")
    elif mnemonic == "movem" and not any(map(parse_list, operands)):
        node.errors.append(f"cannot tell which registers {text} uses")
    follow(node.index + 1)
