"""Lint a set of assembly source files."""

import itertools
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path

from asmlint.findings import ERROR, WARNING, Finding
from asmlint.flow import Node, State, analyse, step
from asmlint.graph import Graph, build_graph
from asmlint.header import Field
from asmlint.reader import read_source
from asmlint.registers import STACK, canonical
from asmlint.routines import Routine, check_label, check_orphans, find_routines
from asmlint.source import Statement, is_local, problem

DEFAULT_RESERVED = ("a5", "a6")
# With more different conditions of conditional assembly than this in one
# routine, their combinations are no longer checked one by one.
MAX_CONDITIONS = 8


@dataclass
class Unit:
    """One source file given on the command line, with all it includes."""

    statements: list[Statement]
    routines: list[Routine] = field(default_factory=list)
    orphans: list[Statement] = field(default_factory=list)
    labels: set[str] = field(default_factory=set)
    exports: set[str] = field(default_factory=set)

    def __post_init__(self) -> None:
        self.routines, self.orphans = find_routines(self.statements)
        for statement in self.statements:
            if statement.label:
                self.labels.add(statement.label)
            if statement.mnemonic in ("xdef", "public", "global"):
                self.exports.update(statement.operands)


def resolve(name: str, unit: Unit, units: list[Unit]) -> set[str] | str:
    """Find the routine a call in ``unit`` refers to.

    Returns the registers its header declares as changed, or the reason the
    call cannot be analysed. A routine in the same unit comes first, then
    exported routines of the other units, then their other global labels.
    """
    for routine in unit.routines:
        if routine.header.name == name:
            return routine.declared
    if is_local(name) or name in unit.labels:
        return "it has no routine header"
    found: dict[bool, dict[tuple[str, int], Routine]] = {True: {}, False: {}}
    for other in units:
        for routine in other.routines:
            if routine.header.name == name:
                place = (routine.header.file, routine.header.line)
                found[name in other.exports][place] = routine
    candidates = list((found[True] or found[False]).values())
    if not candidates:
        return "no routine of that name in the files given"
    if len(candidates) > 1:
        return "several files define a routine of that name"
    return candidates[0].declared


@dataclass
class Summary:
    """What the configurations of a routine checked so far have shown."""

    findings: list[Finding] = field(default_factory=list)
    reached: set[int] = field(default_factory=set)  # nodes some path reaches
    changed: set[str] = field(default_factory=set)  # registers changed at an exit
    returns: bool = False
    is_interrupt: bool = False
    # False when some code could not be analysed, so that what the routine
    # changes is not fully known.
    analysed: bool = True


def configurations(nodes: list[Node]) -> list[dict[str, bool]]:
    """Return every combination of outcomes of a routine's conditional assembly.

    Each is checked on its own, so that two conditionals testing the same
    thing are taken the same way. With too many different conditions there is
    a single configuration in which every conditional goes both ways.
    """
    conditions = sorted({node.condition for node in nodes if node.kind == "fork"})
    if len(conditions) > MAX_CONDITIONS:
        return [{}]
    outcomes = itertools.product((False, True), repeat=len(conditions))
    return [dict(zip(conditions, values, strict=True)) for values in outcomes]


def check_unreachable(
    routine: Routine, graph: Graph, reached: set[int]
) -> list[Finding]:
    """Report code that no path from the routine's entry reaches."""
    findings = []
    reachable = True
    for index, node in enumerate(graph.nodes):
        was_reachable = reachable
        if node.kind in ("fork", "skip"):
            continue
        reachable = index in reached or node.is_data
        if reachable:
            continue
        where = node.statement
        if index in graph.entries:
            where = graph.entries[index]
            message = f"{where.label} has code but no routine header"
            findings.append(Finding(where.file, where.line, ERROR, message))
        elif was_reachable:
            message = f"unreachable code in {routine.header.title} is not checked"
            findings.append(problem(where, message, WARNING))
    return findings


def check_reserved(
    routine: Routine, graph: Graph, states: list[State | None], reserved: set[str]
) -> list[Finding]:
    """Report writes to reserved registers that no annotation allows.

    Popping a saved register back is not a write, but any other write is
    reported even when the register is restored afterwards.
    """
    findings = []
    for node, before in zip(graph.nodes, states, strict=True):
        if before is None or node.is_data:
            continue
        allowed = set(routine.allowed)
        if "allow" in node.annotations:
            allowed |= node.annotations["allow"].registers
        written = step(State(stack=before.stack), node).registers
        causes = dict.fromkeys(written, "written")
        for call in node.calls:
            causes.update(dict.fromkeys(call.registers, f"clobbered by {call.via}"))
        for register in sorted((causes.keys() & reserved) - allowed):
            message = (
                f"reserved register {register} is {causes[register]}"
                f" in {routine.header.title}"
            )
            findings.append(problem(node.statement, message))
    return findings


@dataclass
class Exits:
    """What a routine has changed at the points where it ends.

    The marks are (register, node index) pairs naming the instructions that
    changed a register. ``changed`` is for normal returns and tail calls,
    ``unpreserved`` for returns from an interrupt handler.
    """

    changed: set[tuple[str, int]] = field(default_factory=set)
    unpreserved: set[tuple[str, int]] = field(default_factory=set)
    unbalanced: list[Node] = field(default_factory=list)
    returns: bool = False
    is_interrupt: bool = False


def collect_exits(nodes: list[Node], states: list[State | None]) -> Exits:
    """Gather the state at every reachable exit of a routine."""
    exits = Exits()
    for node, before in zip(nodes, states, strict=True):
        if before is None or not node.exit:
            continue
        exits.returns = True
        after = step(before, node)
        marks = set(after.dirty)
        for call in node.calls:
            if call.tail:
                marks |= {(register, node.index) for register in call.registers}
        if after.stack != () or (STACK, node.index) in marks:
            marks.add((STACK, node.index))
            exits.unbalanced.append(node)
        if node.exit == "rte":
            exits.is_interrupt = True
            exits.unpreserved |= marks
        else:
            exits.changed |= marks
    return exits


def first_cause(nodes: list[Node], marks: set[tuple[str, int]], register: str) -> Node:
    """Return the first instruction that the marks blame for changing a register."""
    return nodes[min(index for name, index in marks if name == register)]


def check_paths(
    routine: Routine,
    graph: Graph,
    states: list[State | None],
    reserved: set[str],
    summary: Summary,
) -> None:
    """Check the paths through a routine in one configuration.

    ``states`` holds the state before each node the configuration reaches.
    """
    header = routine.header
    title = header.title
    nodes = graph.nodes

    def report(statement: Statement, message: str) -> None:
        summary.findings.append(problem(statement, message))

    summary.findings += check_reserved(routine, graph, states, reserved)
    for node, before in zip(nodes, states, strict=True):
        if before is None:
            continue
        summary.reached.add(node.index)
        if node.is_data:
            report(node.statement, f"execution runs into data in {title}")
        for error in node.errors:
            report(node.statement, error)
        if node.falls_off:
            report(node.statement, f"execution runs off the end of {title}")
        if node.is_data or node.errors or node.falls_off:
            summary.analysed = False

    exits = collect_exits(nodes, states)
    declared = routine.declared
    changed = {register for register, _ in exits.changed}
    unpreserved = {register for register, _ in exits.unpreserved}
    summary.changed |= changed | unpreserved
    summary.returns = summary.returns or exits.returns
    summary.is_interrupt = summary.is_interrupt or exits.is_interrupt
    for node in exits.unbalanced:
        if STACK not in declared or node.exit == "rte":
            message = f"the stack is not balanced when {title} returns here"
            report(node.statement, message)
    for register in sorted(changed - declared - {STACK}):
        culprit = first_cause(nodes, exits.changed, register)
        subject = register
        if register in header.registers("In"):
            subject = f"In register {register}"
        cause = "written"
        for call in culprit.calls:
            if register in call.registers:
                cause = f"clobbered by {call.via}"
        message = (
            f"{subject} is {cause} but not listed under Out or Clobbers of {title}"
        )
        report(culprit.statement, message)
    for register in sorted(unpreserved - {STACK}):
        culprit = first_cause(nodes, exits.unpreserved, register)
        message = f"interrupt handler {title} must preserve {register}"
        report(culprit.statement, message)


def check_routine(routine: Routine, graph: Graph, reserved: set[str]) -> list[Finding]:
    """Compare what a routine does to registers with what its header declares."""
    header = routine.header
    title = header.title
    summary = Summary()
    for choices in configurations(graph.nodes):
        states = analyse(graph.nodes, choices)
        check_paths(routine, graph, states, reserved, summary)
    findings = header.problems + routine.problems + check_label(routine)
    findings += graph.problems + summary.findings
    findings += check_unreachable(routine, graph, summary.reached)

    def report(where: Field, message: str, severity: str) -> None:
        findings.append(Finding(header.file, where.line, severity, message))

    clobbers = header.fields.get("Clobbers")
    if summary.is_interrupt and clobbers and clobbers.registers:
        message = f"the header of interrupt handler {title} must say Clobbers: -"
        report(clobbers, message, ERROR)
    if not (summary.returns and summary.analysed):
        return findings  # nothing can be called stale
    for name in ("Out", "Clobbers"):
        if name == "Clobbers" and summary.is_interrupt:
            continue
        for register in sorted(header.registers(name) - summary.changed):
            message = (
                f"{register} is listed under {name} of {title} but is never changed"
            )
            report(header.fields[name], message, WARNING)
    return findings


def lint_files(
    paths: Iterable[Path],
    reserved: Iterable[str] = DEFAULT_RESERVED,
    include_dirs: Iterable[Path] = (),
) -> list[Finding]:
    """Lint the given source files together and return the sorted findings.

    ``reserved`` names the registers that may not be written without a
    ``lint: allow`` annotation. ``include_dirs`` are searched for include files.
    """
    reserved = {canonical(name) or name for name in reserved}
    findings: set[Finding] = set()
    units = []
    for path in paths:
        statements, problems = read_source(Path(path), include_dirs)
        findings.update(problems)
        units.append(Unit(statements))
    for unit in units:
        findings.update(check_orphans(unit.orphans))
        for routine, following in zip(unit.routines, [*unit.routines[1:], None]):
            graph = build_graph(
                routine, following, lambda name, unit=unit: resolve(name, unit, units)
            )
            findings.update(check_routine(routine, graph, reserved))
    return sorted(findings)
