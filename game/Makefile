# Galaga for the Amiga 500
# make            build the executable and a bootable disk image
# make run        boot the disk in FS-UAE (stock A500, Kickstart 1.3)
# make lint       check every routine's header against its code (also part of the build)
# make test       run the test builds in FS-UAE: frame timing, and the sound
#                 driver against the arcade model
# DEFS="-DRASTER_METER=1" and the like override include/config.i

DEFS   ?=
ROM    ?= ../original/galaga.zip
KICK   ?= $(HOME)/Documents/FS-UAE/Kickstarts/kick34005.A500
UAE     = fs-uae --amiga_model=A500 --kickstart_file=$(KICK) --slow_memory=0

# startup.o must be first: the program starts at the top of the first object
OBJECTS = build/startup.o build/main.o build/demo.o build/video.o build/stars.o \
	build/formation.o build/flyers.o build/sound.o build/gfx.o build/state.o
# built from the user's own ROM set; never committed
GENERATED = build/snd_data.i build/snd_chip.bin build/sndtest_script.i \
	build/stars.bin build/starev.bin \
	build/gfx.i build/enemies.bin build/sprites.bin build/font.bin
INCLUDES = $(wildcard include/*.i)

all: build/galaga.adf

build/%.o: src/%.s $(INCLUDES) $(GENERATED) FORCE
	@mkdir -p build
	vasmm68k_mot -quiet -Fhunk -m68000 -Iinclude -Ibuild $(DEFS) -o $@ $<

build/snd_data.i build/snd_chip.bin: tools/make_sound_data.py $(ROM)
	@mkdir -p build
	python3 tools/make_sound_data.py $(ROM) build

build/gfx.i build/enemies.bin build/sprites.bin build/font.bin: tools/make_gfx.py $(ROM)
	@mkdir -p build
	python3 tools/make_gfx.py $(ROM) build

build/stars.bin build/starev.bin: tools/make_stars.py
	@mkdir -p build
	python3 tools/make_stars.py build

build/sndtest_script.i: tools/sndtest.py
	@mkdir -p build
	python3 tools/sndtest.py script $@

build/galaga: $(OBJECTS) lint
	vlink -bamigahunk -s -o $@ $(OBJECTS)

# a header that has drifted from its code breaks the build
lint: $(GENERATED)
	uv run -q --project ../asmlint asmlint -I include -I build src/*.s

build/galaga.adf: build/galaga
	@printf 'galaga\n' > build/startup-sequence
	xdftool $@ format galaga + boot install + makedir S \
		+ write build/startup-sequence S/startup-sequence + write build/galaga

run: build/galaga.adf
	$(UAE) --floppy_drive_0=$(CURDIR)/build/galaga.adf

test:
	tools/test.sh
	tools/test_sound.sh

clean:
	rm -rf build

FORCE:
.PHONY: all run test lint clean FORCE
