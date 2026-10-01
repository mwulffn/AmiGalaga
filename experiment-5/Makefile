# experiment-5: experiment-4 with fading stars
NFLY  ?= 10
DEFS  ?=
ROM   ?= ../original/galaga.zip
KICK  ?= $(HOME)/Documents/FS-UAE/Kickstarts/kick34005.A500
UAE    = fs-uae --amiga_model=A500 --kickstart_file=$(KICK) --slow_memory=0
EXP1   = ../experiment-1

GFX = build/enemies.bin build/sprites.bin build/font.bin build/gfx.i
STARS = build/stars.bin build/starev.bin

all: build/exp5.adf

$(GFX): $(EXP1)/tools/extract_gfx.py $(ROM)
	@mkdir -p build
	python3 $(EXP1)/tools/extract_gfx.py $(ROM) build

build/exp5: $(STARS) src/main.s $(EXP1)/src/measure.i $(GFX) FORCE
	vasmm68k_mot -quiet -Fhunkexe -kick1hunks -nosym -DNFLY=$(NFLY) $(DEFS) \
		-Ibuild -I$(EXP1)/src -o $@ src/main.s

build/exp5.adf: build/exp5
	@printf 'exp5\n' > build/startup-sequence
	xdftool $@ format exp5 + boot install + makedir S \
		+ write build/startup-sequence S/startup-sequence + write build/exp5

run: build/exp5.adf
	$(UAE) --floppy_drive_0=$(CURDIR)/build/exp5.adf

clean:
	rm -rf build

FORCE:
.PHONY: all run clean FORCE

$(STARS): tools/make_stars.py
	@mkdir -p build
	python3 tools/make_stars.py build
