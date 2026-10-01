"""Include files, conditional assembly and other directives."""

from pathlib import Path

HEADER = """
;--
; Foo
; In:       -
; Out:      -
; Clobbers: {clobbers}
Foo:
"""

HELPER = """\
;--
; Helper
; In:       -
; Out:      -
; Clobbers: -
Helper:
	moveq	#0,d0
	rts
"""


def routine(body: str, clobbers: str = "-") -> str:
    """Return a routine Foo with the given body; the body starts on line 8."""
    return HEADER.format(clobbers=clobbers) + body


def test_routines_in_include_files_are_linted(lint):
    source = routine('\tbsr\tHelper\n\trts\n\tinclude\t"helper.i"\n')
    assert lint(source, helper_i=HELPER) == [
        (
            "helper.i:7: error: d0 is written but not listed under Out or Clobbers"
            " of Helper"
        )
    ]


def test_missing_include_file_is_an_error(lint):
    assert lint('\tinclude\t"nowhere.i"\n') == [
        "main.s:1: error: cannot find the include file 'nowhere.i'"
    ]


def test_include_directories(lint, tmp_path: Path):
    (tmp_path / "build").mkdir()
    (tmp_path / "build" / "gen.i").write_text(HELPER)
    source = '\tinclude\t"gen.i"\n'
    expected = [
        (
            "build/gen.i:7: error: d0 is written but not listed under Out or Clobbers"
            " of Helper"
        )
    ]
    assert lint(source, options={"include_dirs": [tmp_path / "build"]}) == expected
    assert lint('\tincdir\t"build"\n' + source) == expected


def test_file_included_twice_is_read_once(lint):
    source = '\tinclude\t"helper.i"\n\tinclude helper.i\n'
    assert len(lint(source, helper_i=HELPER)) == 1


def test_both_branches_of_a_conditional_are_checked(lint):
    source = routine("""\
	ifd	DEBUG
	moveq	#0,d1
	rts
	else
	moveq	#0,d2
	endc
	rts
""")
    assert lint(source) == [
        "main.s:9: error: d1 is written but not listed under Out or Clobbers of Foo",
        "main.s:12: error: d2 is written but not listed under Out or Clobbers of Foo",
    ]


def test_each_branch_of_a_conditional_is_a_path_of_its_own(lint):
    source = routine("""\
	if	FAST
	move.l	d2,-(sp)
	moveq	#0,d2
	move.l	(sp)+,d2
	else
	movem.l	d2-d3,-(sp)
	moveq	#0,d2
	moveq	#0,d3
	movem.l	(sp)+,d2-d3
	endc
	rts
""")
    assert lint(source) == []


def test_conditional_without_else_may_be_skipped(lint):
    source = routine("""\
	ifne	DEBUG
	move.l	d2,-(sp)
	endc
	rts
""")
    assert lint(source) == [
        "main.s:11: error: the stack is not balanced when Foo returns here"
    ]


def test_nested_conditionals_and_elseif(lint):
    source = routine("""\
	ifd	A
	ifd	B
	moveq	#0,d1
	else
	moveq	#0,d2
	endif
	elseif
	moveq	#0,d3
	endc
	rts
""")
    assert [finding.split(":")[1] for finding in lint(source)] == ["10", "12", "15"]


def test_body_of_a_repeat_block_is_checked(lint):
    source = routine("""\
	rept	4
	move.w	(a0)+,d0
	endr
	rts
""")
    assert [finding.split(" ")[2] for finding in lint(source)] == ["a0", "d0"]


def test_register_aliases(lint):
    source = routine(
        """\
Count	equr	d5
Ptr	equr	a3
SAVED	reg	d2-d3/a2
	movem.l	SAVED,-(sp)
	moveq	#0,d2
	move.l	d2,d3
	move.l	d3,a2
	move.w	(Ptr)+,Count
	movem.l	(sp)+,SAVED
	rts
""",
        clobbers="d5",
    )
    assert lint(source) == [
        "main.s:15: error: a3 is written but not listed under Out or Clobbers of Foo"
    ]


def test_block_comments_and_end_are_skipped(lint):
    source = routine("""\
	rem
	moveq	#0,d1
	erem
	rts
	end
Junk:
	moveq	#0,d2
""")
    assert lint(source) == []


def test_common_directives_inside_a_routine(lint):
    source = routine("""\
	section	code,code
	xdef	Foo
	xref	Elsewhere
SIZE	equ	4
COUNT	=	2
	rsreset
t_x	rs.w	1
	opt	o+
	cnop	0,4
	ds.w	0
	even
	rts
""")
    assert lint(source) == []


def test_block_comment_without_end_is_an_error(lint):
    assert lint("\trem\n\tmoveq\t#0,d0\n") == ["main.s:1: error: rem has no erem"]


def test_routine_in_an_include_shared_by_two_files_is_reported_once(lint):
    source = '\tinclude\t"helper.i"\n'
    assert len(lint(source, other_s=source, helper_i=HELPER)) == 1


def test_conditional_around_whole_routines(lint):
    one = routine("\tmoveq\t#0,d0\n\trts\n", clobbers="d0")
    two = routine("\tmoveq\t#0,d1\n\trts\n", clobbers="d1")
    source = f"\tifd\tFAST\n{one}\telse\n{two}\tendc\n"
    assert lint(source) == []


def test_conditionals_on_the_same_symbol_go_the_same_way(lint):
    source = routine("""\
	ifd	MEASURE
	move.l	d2,-(sp)
	endc
	moveq	#0,d1
	ifnd	MEASURE
	nop
	else
	moveq	#0,d2
	move.l	(sp)+,d2
	endc
	if	DEBUG
	move.w	d1,-(sp)
	endc
	ifeq	DEBUG
	nop
	endc
	ifne	DEBUG
	addq.l	#2,sp
	endc
	rts
""")
    assert lint(source) == [
        "main.s:11: error: d1 is written but not listed under Out or Clobbers of Foo"
    ]


def test_conditionals_on_different_symbols_are_independent(lint):
    source = routine("""\
	ifd	MEASURE
	move.l	d2,-(sp)
	endc
	ifd	DEBUG
	move.l	(sp)+,d2
	endc
	rts
""")
    assert lint(source) == [
        "main.s:12: error: d2 is written but not listed under Out or Clobbers of Foo",
        "main.s:14: error: the stack is not balanced when Foo returns here",
    ]


def test_elif_chain(lint):
    source = routine("""\
	if	SPEED=1
	moveq	#0,d1
	elif	SPEED=2
	moveq	#0,d2
	else
	moveq	#0,d3
	endc
	rts
""")
    assert [finding.split(":")[1] for finding in lint(source)] == ["9", "11", "13"]


def test_code_reached_in_one_configuration_is_not_unreachable(lint):
    source = routine(
        """\
	ifd	SHORT
	rts
	endc
	moveq	#0,d1
	rts
""",
        clobbers="d1",
    )
    assert lint(source) == []


def test_register_changed_in_one_configuration_is_not_stale(lint):
    source = routine(
        """\
	ifd	DEBUG
	moveq	#0,d1
	endc
	rts
""",
        clobbers="d1",
    )
    assert lint(source) == []


def test_many_different_conditions_are_still_checked(lint):
    blocks = "".join(f"\tifd\tFLAG{n}\n\tmoveq\t#0,d1\n\tendc\n" for n in range(12))
    assert lint(routine(blocks + "\trts\n")) == [
        "main.s:9: error: d1 is written but not listed under Out or Clobbers of Foo"
    ]
