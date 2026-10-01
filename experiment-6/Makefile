# experiment-6: experiment-5 plus the sound driver
NFLY  ?= 10
DEFS  ?=
ROM   ?= ../original/galaga.zip
KICK  ?= $(HOME)/Documents/FS-UAE/Kickstarts/kick34005.A500
UAE    = fs-uae --amiga_model=A500 --kickstart_file=$(KICK) --slow_memory=0
EXP1   = ../experiment-1

GFX = build/enemies.bin build/sprites.bin build/font.bin build/gfx.i
STARS = build/stars.bin build/starev.bin
SOUND = build/snd_data.i build/snd_chip.bin build/sndtest_script.i

all: build/exp6.adf

$(GFX): $(EXP1)/tools/extract_gfx.py $(ROM)
	@mkdir -p build
	python3 $(EXP1)/tools/extract_gfx.py $(ROM) build

build/exp6: $(STARS) $(SOUND) src/main.s src/sound.s $(EXP1)/src/measure.i $(GFX) FORCE
	vasmm68k_mot -quiet -Fhunkexe -kick1hunks -nosym -DNFLY=$(NFLY) $(DEFS) \
		-Ibuild -Isrc -I$(EXP1)/src -o $@ src/main.s

build/exp6.adf: build/exp6
	@printf 'exp6\n' > build/startup-sequence
	xdftool $@ format exp6 + boot install + makedir S \
		+ write build/startup-sequence S/startup-sequence + write build/exp6

run: build/exp6.adf
	$(UAE) --floppy_drive_0=$(CURDIR)/build/exp6.adf

clean:
	rm -rf build

FORCE:
.PHONY: all run clean FORCE

$(STARS): ../experiment-5/tools/make_stars.py
	@mkdir -p build
	python3 ../experiment-5/tools/make_stars.py build

build/snd_data.i build/snd_chip.bin: tools/make_sound_data.py $(ROM)
	@mkdir -p build
	python3 tools/make_sound_data.py $(ROM) build

build/sndtest_script.i: tools/sndtest.py
	@mkdir -p build
	python3 tools/sndtest.py script $@
