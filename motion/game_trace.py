"""Read a trace written by trace_game.lua: the main CPU's memory, frame by frame."""

from pathlib import Path

REGIONS = (
    (0x9200, 0x100), (0x9100, 0xF0), (0x8800, 0x80), (0x9800, 0x60), (0x9900, 0x20),
    (0x99C0, 0x10), (0x9000, 0x40), (0x9300, 0x80), (0x9B00, 0x80), (0x8B00, 0x80),
)  # fmt: skip
SIZE = sum(n for _, n in REGIONS)

# where things are (the arcade's RAM)
FRAME = 0x92A0  # counts frames
FLYING = 0x9287  # enemies in flight, as of the previous frame
ALIVE = 0x92A7  # enemies left
LAST_STAND = 0x92AA  # few enough left that they attack without pause
GAME_TIMERS = 0x92AC
DIVE_TIMERS = 0x92C0  # 3 timers, a spare byte, their 3 reload values
BOSS_POOL = 0x92CA  # 4 x (object, script address): a boss and its escorts waiting to launch
ENEMIES_ON = 0x920B
SLOTS = 0x9100  # 12 x 20 bytes
STATES = 0x8800  # per object: state, slot
TASKS = 0x9000
PLAYER = 0x9820  # the player's state
STAGE, CAPTURE_BOSS, CAPTURING, BOSS_TOGGLE, SPECIAL = 0x9821, 0x9828, 0x982B, 0x982C, 0x982D
PARMS = 0x99C0
SPRITE_POS, SPRITE_CTRL, SPRITE_CODE = 0x9300, 0x9B00, 0x8B00
HOME_X, HOME_LOC = 0x9800, 0x9900


class Frame:
    def __init__(self, data: bytes) -> None:
        self.data = data

    def mem(self, addr: int, n: int = 1) -> bytes:
        at = 0
        for base, size in REGIONS:
            if base <= addr < base + size:
                return self.data[at + addr - base : at + addr - base + n]
            at += size
        raise KeyError(hex(addr))

    def byte(self, addr: int) -> int:
        return self.mem(addr)[0]

    def slot(self, i: int) -> bytes:
        return self.mem(SLOTS + 20 * i, 20)

    def state(self, obj: int) -> int:
        return self.byte(STATES + obj)


def load(path: str) -> list[Frame]:
    data = Path(path).read_bytes()
    return [Frame(data[i : i + SIZE]) for i in range(0, len(data) - SIZE + 1, SIZE)]
