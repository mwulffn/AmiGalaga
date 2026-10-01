"""The routine header and the basic comparison with the code."""


def test_correct_routine_has_no_findings(lint):
    source = """
;--
; AddOne
; In:       d0 = value
; Out:      d0 = value + 1
; Clobbers: -
AddOne:
	addq.l	#1,d0
	rts
"""
    assert lint(source) == []


def test_write_to_undeclared_register_is_an_error(lint):
    source = """
;--
; AddOne
; In:       d0 = value
; Out:      d0 = value + 1
; Clobbers: -
AddOne:
	moveq	#1,d1
	add.l	d1,d0
	rts
"""
    assert lint(source) == [
        "main.s:8: error: d1 is written but not listed under Out or Clobbers of AddOne"
    ]


def test_changed_in_register_must_be_declared(lint):
    source = """
;--
; Store
; In:       a0 = destination, d0 = value
; Out:      -
; Clobbers: -
Store:
	move.w	d0,(a0)
	lsr.w	#8,d0
	rts
"""
    assert lint(source) == [
        (
            "main.s:9: error: In register d0 is written but not listed under Out or"
            " Clobbers of Store"
        )
    ]


def test_flags_in_out_field_are_accepted(lint):
    source = """
;--
; Find
; In:       d0.w = key, a0 = table
; Out:      Z = found, a0 = entry
; Clobbers: d1/d2
Find:
	move.w	(a0),d1
	move.w	d1,d2
	addq.l	#2,a0
	cmp.w	d0,d2
	rts
"""
    assert lint(source) == []


def test_code_without_header_is_an_error(lint):
    source = """
VALUE	equ	5

Orphan:
	moveq	#VALUE,d0
.Done:
	rts
"""
    assert lint(source) == ["main.s:4: error: Orphan has code but no routine header"]


def test_missing_field_is_an_error(lint):
    source = """
;--
; Foo
; In:       -
; Clobbers: -
Foo:
	rts
"""
    assert lint(source) == ["main.s:2: error: header of Foo has no Out field"]


def test_empty_field_is_an_error(lint):
    source = """
;--
; Foo
; In:
; Out:      -
; Clobbers: -
Foo:
	rts
"""
    assert lint(source) == [
        "main.s:4: error: the In field of Foo is empty; write - for nothing"
    ]


def test_header_name_must_match_label(lint):
    source = """
;--
; Foo
; In:       -
; Out:      -
; Clobbers: -
Bar:
	rts
"""
    assert lint(source) == [
        "main.s:7: error: header names Foo but the label that follows is Bar"
    ]


def test_header_without_name_is_an_error(lint):
    source = """
;--
; In:       -
; Out:      -
; Clobbers: -
Foo:
	rts
"""
    assert lint(source) == ["main.s:2: error: header has no routine name"]


def test_header_must_be_followed_by_a_label(lint):
    source = """
;--
; Foo
; In:       -
; Out:      -
; Clobbers: -
	even
	rts
"""
    assert lint(source) == ["main.s:8: error: header of Foo is not followed by a label"]


def test_unparsable_clobbers_field_is_an_error(lint):
    source = """
;--
; Foo
; In:       -
; Out:      -
; Clobbers: d0 and d1
Foo:
	moveq	#0,d0
	moveq	#0,d1
	rts
"""
    assert lint(source)[0] == (
        "main.s:6: error: cannot parse the Clobbers field of Foo: 'd0 and d1'"
    )


def test_header_fields_may_continue_and_be_followed_by_prose(lint):
    source = """
;--
; Foo
; In:       d0 = first value,
;           d1 = second value
; Out:      d0 = sum
; Clobbers: d2,
;           a0-a1
;
; Adds things. Uses d5 = nothing at all.
Foo:
	add.l	d1,d0
	move.l	d0,d2
	move.l	d0,a0
	move.l	d0,a1
	moveq	#0,d1
	rts
"""
    assert lint(source) == [
        (
            "main.s:16: error: In register d1 is written but not listed under Out or"
            " Clobbers of Foo"
        )
    ]


def test_banner_comment_is_not_a_header(lint):
    source = """
;--------
; Notes about this file.
;--------
VALUE	equ	1
"""
    assert lint(source) == []


def test_header_fields_may_be_indented(lint):
    source = """
;--
;   Foo
;   In:       -
;   Out:      -
;   Clobbers: d0
Foo:
	moveq	#0,d0
	rts
"""
    assert lint(source) == []
