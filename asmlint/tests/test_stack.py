"""Registers saved on the stack and restored count as preserved."""

HEADER = """
;--
; Foo
; In:       d0 = value
; Out:      d0 = result
; Clobbers: {clobbers}
Foo:
"""


def routine(body: str, clobbers: str = "-") -> str:
    """Return a routine Foo with the given body; the body starts on line 8."""
    return HEADER.format(clobbers=clobbers) + body


def test_movem_save_and_restore_preserves(lint):
    source = routine("""\
	movem.l	d2-d3/a2,-(sp)
	move.l	d0,d2
	move.l	d2,d3
	move.l	d3,a2
	move.l	a2,d0
	movem.l	(sp)+,d2-d3/a2
	rts
""")
    assert lint(source) == []


def test_single_push_and_pop_preserves(lint):
    source = routine("""\
	move.l	d2,-(sp)
	move.l	a2,-(a7)
	move.l	d0,d2
	move.l	d2,a2
	move.l	a2,d0
	movea.l	(a7)+,a2
	move.l	(sp)+,d2
	rts
""")
    assert lint(source) == []


def test_pops_in_the_wrong_order_do_not_restore(lint):
    source = routine("""\
	move.l	d2,-(sp)
	move.l	d3,-(sp)
	moveq	#0,d2
	moveq	#0,d3
	move.l	(sp)+,d2
	move.l	(sp)+,d3
	moveq	#0,d0
	rts
""")
    assert lint(source) == [
        "main.s:10: error: d2 is written but not listed under Out or Clobbers of Foo",
        "main.s:11: error: d3 is written but not listed under Out or Clobbers of Foo",
    ]


def test_movem_restoring_fewer_registers_than_saved(lint):
    source = routine("""\
	movem.l	d2-d4,-(sp)
	moveq	#0,d2
	moveq	#0,d3
	moveq	#0,d4
	movem.l	(sp)+,d2-d3
	addq.l	#4,sp
	moveq	#0,d0
	rts
""")
    assert lint(source) == [
        "main.s:11: error: d4 is written but not listed under Out or Clobbers of Foo"
    ]


def test_word_sized_save_does_not_preserve(lint):
    source = routine("""\
	move.w	d2,-(sp)
	moveq	#0,d2
	move.w	(sp)+,d2
	moveq	#0,d0
	rts
""")
    assert lint(source) == [
        "main.s:9: error: d2 is written but not listed under Out or Clobbers of Foo"
    ]


def test_register_changed_before_it_is_saved_is_not_preserved(lint):
    source = routine("""\
	moveq	#0,d2
	move.l	d2,-(sp)
	move.l	(sp)+,d2
	moveq	#0,d0
	rts
""")
    assert lint(source) == [
        "main.s:8: error: d2 is written but not listed under Out or Clobbers of Foo"
    ]


def test_preserved_register_listed_under_clobbers_is_stale(lint):
    source = routine(
        """\
	move.l	d2,-(sp)
	move.l	d0,d2
	move.l	(sp)+,d2
	rts
""",
        clobbers="d1, d2",
    )
    assert lint(source) == [
        "main.s:5: warning: d0 is listed under Out of Foo but is never changed",
        "main.s:6: warning: d1 is listed under Clobbers of Foo but is never changed",
        "main.s:6: warning: d2 is listed under Clobbers of Foo but is never changed",
    ]


def test_unbalanced_stack_is_an_error(lint):
    source = routine("""\
	move.l	d2,-(sp)
	moveq	#0,d0
	rts
""")
    assert lint(source) == [
        "main.s:10: error: the stack is not balanced when Foo returns here"
    ]


def test_stack_space_reserved_and_released(lint):
    source = routine("""\
	subq.l	#8,sp
	lea	-16(sp),sp
	move.w	d0,-(sp)
	clr.b	-(sp)
	pea	(a0)
	moveq	#0,d0
	addq.l	#4,sp
	tst.b	(sp)+
	move.w	(sp)+,d0
	lea	16(sp),sp
	adda.w	#8,sp
	rts
""")
    assert lint(source) == []


def test_releasing_stack_space_by_an_unknown_amount_is_reported(lint):
    source = routine("""\
	lea	-FRAME(sp),sp
	moveq	#0,d0
	lea	OTHER(sp),sp
	rts
""")
    assert lint(source) == [
        "main.s:11: error: the stack is not balanced when Foo returns here"
    ]


def test_stack_space_with_a_named_or_hexadecimal_size(lint):
    source = routine("""\
	move.l	d2,-(sp)
	lea	-FRAME(sp),sp
	sub.w	#LOCALS*2,sp
	lea	-$10(sp),sp
	link	a4,#-FRAME
	moveq	#0,d0
	move.l	d0,d2
	unlk	a4
	lea	($10,sp),sp
	adda.w	#LOCALS*2,sp
	lea	FRAME(sp),sp
	move.l	(sp)+,d2
	rts
""")
    assert lint(source) == []


def test_pushing_a_value_leaves_saved_registers_alone(lint):
    source = routine("""\
	movem.l	d2-d3,-(sp)
	moveq	#0,d2
	moveq	#0,d3
	move.l	#5,-(sp)
	clr.w	-(sp)
	moveq	#0,d0
	addq.l	#6,sp
	movem.l	(sp)+,d2-d3
	rts
""")
    assert lint(source) == []


def test_popping_into_the_stack_pointer_is_reported(lint):
    source = routine("""\
	move.l	sp,-(sp)
	moveq	#0,d0
	move.l	(sp)+,sp
	rts
""")
    assert lint(source) == [
        "main.s:11: error: the stack is not balanced when Foo returns here"
    ]


def test_loading_the_stack_pointer_is_reported_unless_declared(lint):
    body = """\
	moveq	#0,d0
	lea	Stack,sp
	rts
"""
    assert lint(routine(body)) == [
        "main.s:10: error: the stack is not balanced when Foo returns here"
    ]
    assert lint(routine(body, clobbers="sp")) == []


def test_link_and_unlk_preserve_the_frame_pointer(lint):
    source = routine("""\
	link	a4,#-8
	move.l	d0,-4(a4)
	moveq	#0,d0
	unlk	a4
	rts
""")
    assert lint(source) == []


def test_link_without_unlk_is_reported(lint):
    source = routine("""\
	link	a4,#-8
	moveq	#0,d0
	rts
""")
    assert lint(source) == [
        "main.s:8: error: a4 is written but not listed under Out or Clobbers of Foo",
        "main.s:10: error: the stack is not balanced when Foo returns here",
    ]


def test_writing_into_the_stack_forgets_saved_registers(lint):
    source = routine("""\
	move.l	d2,-(sp)
	move.l	d0,d2
	move.l	d0,(sp)
	move.l	(sp)+,d2
	moveq	#0,d0
	rts
""")
    assert lint(source) == [
        "main.s:9: error: d2 is written but not listed under Out or Clobbers of Foo"
    ]


def test_parameter_popped_from_the_stack_is_a_write(lint):
    source = routine("""\
	move.l	d0,-(sp)
	move.l	(sp)+,d1
	rts
""")
    assert lint(source) == [
        "main.s:5: warning: d0 is listed under Out of Foo but is never changed",
        "main.s:9: error: d1 is written but not listed under Out or Clobbers of Foo",
    ]


def test_movem_with_an_unknown_register_list_is_an_error(lint):
    source = routine("""\
	movem.l	SAVED,-(sp)
	moveq	#0,d0
	movem.l	(sp)+,SAVED
	rts
""")
    assert lint(source) == [
        "main.s:8: error: cannot tell which registers movem SAVED,-(sp) uses",
        "main.s:10: error: cannot tell which registers movem (sp)+,SAVED uses",
    ]
