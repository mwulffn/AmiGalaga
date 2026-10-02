"""Check that the ROM set is the one the game is built from, before anything is built.

    python3 tools/check_rom.py ../original/galaga.zip [stamp]

The build reads MAME's `galaga` set, Namco revision B. Another set (another revision,
a clone, the same files under other names) would build without a word and give a
game that is wrong in ways that are hard to see, so every file the tools read is
looked for by its name and its checksum, which the zip has for each file. What is
wrong is said in a way that says what to do about it. If all is well and a stamp
is named, it is written, for make to see that the check has been made; a stamp
that says the same already is left as it is, so that make builds nothing again.
"""

import sys
import zipfile
from pathlib import Path

# the files the tools read, with the CRC-32 of each in the Namco revision B set
FILES = {
    "gg1_1b.3p": 0xAB036C9F,  # the main CPU's program
    "gg1_2b.3m": 0xD9232240,
    "gg1_3.2m": 0x753CE503,
    "gg1_4b.2l": 0x499FCC76,
    "gg1_5b.3f": 0xBB5CAAE3,  # the second CPU's: the enemies' flight
    "gg1_7b.2c": 0xD016686B,  # the third CPU's: sound
    "gg1_9.4l": 0x58B2F47C,  # characters
    "gg1_11.4d": 0xAD447C80,  # sprites
    "gg1_10.4f": 0xDD6F1AFC,
    "prom-5.5n": 0x54603C6B,  # palette
    "prom-4.2n": 0x59B6EDAB,  # the characters' colours
    "prom-3.1c": 0x4A04BB6B,  # the sprites' colours
    "prom-1.1d": 0x7A2815B4,  # the sound's waveforms
}
WHERE = (
    "The game is built from MAME's `galaga` ROM set (Namco revision B), which you\n"
    'have to supply: see "Bring your own ROM" in README.md.'
)


def problems(path: Path) -> list[str]:
    """What is wrong with the ROM set at `path`: nothing, if the list is empty."""
    if not path.exists():
        return [
            f"There is no ROM set at {path}.",
            "Put your galaga.zip there, or say where it is: make ROM=/path/to/galaga.zip",
        ]
    try:
        with zipfile.ZipFile(path) as archive:
            found = {info.filename: info.CRC for info in archive.infolist()}
    except zipfile.BadZipFile:
        return [f"{path} is not a zip file."]
    missing = [name for name in FILES if name not in found]
    other = [
        name for name, crc in FILES.items() if name in found and found[name] != crc
    ]
    said = []
    if missing:
        said.append(f"{path} has no {', '.join(missing)}.")
        said.append(
            "It is not MAME's `galaga` set: a clone or an older dump has files of"
            " other names."
        )
    if other:
        said.append(f"In {path}, {', '.join(other)} is not the Namco revision B file.")
        said.append("This is another revision of the game, or a damaged file.")
    return said


def main() -> None:
    path = Path(sys.argv[1])
    said = problems(path)
    if said:
        sys.exit("\n".join(["", *said, WHERE, ""]))
    if len(sys.argv) > 2:
        stamp = Path(sys.argv[2])
        stamp.parent.mkdir(parents=True, exist_ok=True)
        says = f"{path.resolve()}: the Namco revision B set\n"
        if not stamp.exists() or stamp.read_text() != says:
            stamp.write_text(says)


if __name__ == "__main__":
    main()
