"""A routine that ends in rte is an interrupt handler and must preserve everything."""

HANDLER = """
;--
; VBlank
; In:       -
; Out:      {out}
; Clobbers: {clobbers}
; lint: allow a5-a6
VBlank:
"""


def handler(body: str, clobbers: str = "-", out: str = "-") -> str:
    """Return a handler VBlank with the given body; the body starts on line 9."""
    return HANDLER.format(clobbers=clobbers, out=out) + body


SAVING = """\
	movem.l	d0-d1/a5-a6,-(sp)
	lea	State,a5
	lea	$dff000,a6
	move.w	$1e(a6),d0
	move.w	d0,d1
	move.w	d1,$9c(a6)
	movem.l	(sp)+,d0-d1/a5-a6
	rte
"""


def test_handler_that_restores_everything_is_fine(lint):
    assert lint(handler(SAVING)) == []


def test_handler_must_preserve_every_register(lint):
    body = SAVING.replace("d0-d1/a5-a6,-(sp)", "d0/a5-a6,-(sp)")
    body = body.replace("(sp)+,d0-d1/a5-a6", "(sp)+,d0/a5-a6")
    expected = ["main.s:13: error: interrupt handler VBlank must preserve d1"]
    assert lint(handler(body)) == expected
    assert lint(handler(body, out="d1 = status")) == expected


def test_handler_header_must_say_clobbers_nothing(lint):
    assert lint(handler(SAVING, clobbers="d0")) == [
        "main.s:6: error: the header of interrupt handler VBlank must say Clobbers: -"
    ]


def test_handler_must_leave_the_stack_balanced(lint):
    body = SAVING.replace("(sp)+,d0-d1/a5-a6", "(sp)+,d0-d1/a5")
    assert lint(handler(body))[-1] == (
        "main.s:16: error: the stack is not balanced when VBlank returns here"
    )


def test_handler_inherits_clobbers_of_what_it_calls(lint):
    body = """\
	bsr	Tick
	rte

;--
; Tick
; In:       -
; Out:      -
; Clobbers: d0
Tick:
	moveq	#0,d0
	rts
"""
    assert lint(handler(body)) == [
        "main.s:9: error: interrupt handler VBlank must preserve d0"
    ]
