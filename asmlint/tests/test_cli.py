"""The command line."""

import subprocess
import sys
from pathlib import Path

import pytest

from asmlint.cli import main

GOOD = """\
;--
; Foo
; In:       -
; Out:      -
; Clobbers: d0
Foo:
	moveq	#0,d0
	rts
"""
STALE = GOOD.replace("Clobbers: d0", "Clobbers: d0/d1")
BAD = GOOD.replace("Clobbers: d0", "Clobbers: -")


def clearing(register: str) -> str:
    """Return the good routine changed to clear an address register instead."""
    text = GOOD.replace("moveq\t#0,d0", f"suba.l\t{register},{register}")
    return text.replace("Clobbers: d0", f"Clobbers: {register}")


@pytest.fixture
def write(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Return a function that writes a file in the current directory."""
    monkeypatch.chdir(tmp_path)

    def run(name: str, text: str) -> str:
        Path(name).write_text(text)
        return name

    return run


def test_clean_file_exits_zero_and_prints_nothing(write, capsys):
    assert main([write("good.s", GOOD)]) == 0
    assert capsys.readouterr().out == ""


def test_errors_are_printed_one_per_line_and_exit_one(write, capsys):
    assert main([write("good.s", GOOD), write("bad.s", BAD)]) == 1
    assert capsys.readouterr().out == (
        "bad.s:7: error: d0 is written but not listed under Out or Clobbers of Foo\n"
    )


def test_warnings_alone_exit_zero(write, capsys):
    assert main([write("stale.s", STALE)]) == 0
    assert capsys.readouterr().out == (
        "stale.s:5: warning: d1 is listed under Clobbers of Foo but is never changed\n"
    )


def test_reserved_option(write, capsys):
    name = write("reserved.s", clearing("a4"))
    assert main([name]) == 0
    assert main(["--reserved", "a4,sp", name]) == 1
    assert capsys.readouterr().out == (
        "reserved.s:7: error: reserved register a4 is written in Foo\n"
    )
    assert main(["--reserved", "a8", name]) == 2
    assert "a8 is not a register" in capsys.readouterr().err


def test_no_reserved_registers(write):
    name = write("a5.s", clearing("a5"))
    assert main([name]) == 1
    assert main(["--reserved", "-", name]) == 0


def test_include_directory_option(write, capsys):
    Path("gen").mkdir()
    write("gen/part.i", BAD)
    name = write("main.s", '\tinclude\t"part.i"\n')
    assert main([name]) == 1
    assert "cannot find the include file" in capsys.readouterr().out
    assert main(["-I", "gen", name]) == 1
    assert capsys.readouterr().out.startswith("gen/part.i:7: error: d0 is written")


def test_missing_file_exits_two(write, capsys):
    assert main(["nowhere.s"]) == 2
    assert "nowhere.s" in capsys.readouterr().err


def test_module_can_be_run(write):
    result = subprocess.run(
        [sys.executable, "-m", "asmlint", write("bad.s", BAD)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 1
    assert result.stdout.startswith("bad.s:7: error:")
