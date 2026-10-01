"""Assembler directives the linter needs to recognise (vasm, Motorola syntax)."""

from asmlint.source import Statement, words

# Directives that put data, not code, into the program.
DATA = words("dc dcb ds dx blk dr db dw dl incbin")
# Conditional assembly.
IF = words(
    "if ifeq ifne ifgt ifge iflt ifle ifd ifnd ifc ifnc ifb ifnb"
    " ifmacrod ifmacrond ifp1"
)
ELSE = {"else", "elseif"}  # vasm treats elseif as else
ELSE_IF = {"elif"}
END_IF = {"endc", "endif"}
# Directives that emit nothing and do not change what the code does.
OTHER = words(
    "= equ set fequ equr reg rs rsreset rsset so fo clrso clrfo setso setfo offset"
    " section code code_c code_f data data_c data_f bss bss_c bss_f cseg dseg text"
    " xdef xref nref public global weak comm"
    " even odd cnop align org rorg"
    " include incdir macro endm mexit rept endr end rem erem comment"
    " opt machine mc68000 near far initnear basereg endb inline einline"
    " idnt ttl list nolist page nopage plen llen spc output msource"
    " echo printt printv fail cargs"
)


def is_data(statement: Statement) -> bool:
    """True for a directive that emits data."""
    return statement.mnemonic in DATA and not is_ignored(statement)


def is_ignored(statement: Statement) -> bool:
    """True for a directive that the flow analysis can pass over."""
    if statement.mnemonic == "ds" and statement.operands[:1] == ("0",):
        return True  # only aligns
    return statement.mnemonic in OTHER


def condition(statement: Statement) -> tuple[str, bool]:
    """Return what a conditional tests, and whether it tests for the opposite.

    ``ifd X`` and ``ifnd X`` test the same thing with opposite outcomes, and so
    do ``if X``/``ifne X`` and ``ifeq X``.
    """
    mnemonic = statement.mnemonic
    subject = ",".join(statement.operands)
    if mnemonic in ("ifd", "ifnd"):
        return f"defined {subject}", mnemonic == "ifnd"
    if mnemonic in ("if", "ifne", "ifeq", "elif"):
        return f"nonzero {subject}", mnemonic == "ifeq"
    return f"{mnemonic} {subject}", False
