# experiment-4: experiment-3 plus the copper starfield
NFLY  ?= 10
DEFS  ?=
ROM   ?= ../original/galaga.zip
KICK  ?= $(HOME)/Documents/FS-UAE/Kickstarts/kick34005.A500
UAE    = fs-uae --amiga_model=A500 --kickstart_file=$(KICK) --slow_memory=0
EXP1   = ../experiment-1

GFX = build/enemies.bin build/sprites.bin build/font.bin build/gfx.i
STARS = build/stars.bin

all: build/exp4.adf

$(GFX) &: $(EXP1)/tools/extract_gfx.py $(ROM)
	@mkdir -p build
	python3 $(EXP1)/tools/extract_gfx.py $(ROM) build

build/exp4: $(STARS) src/main.s $(EXP1)/src/measure.i $(GFX) FORCE
	vasmm68k_mot -quiet -Fhunkexe -kick1hunks -nosym -DNFLY=$(NFLY) $(DEFS) \
		-Ibuild -I$(EXP1)/src -o $@ src/main.s

build/exp4.adf: build/exp4
	@printf 'exp4\n' > build/startup-sequence
	xdftool $@ format exp4 + boot install + makedir S \
		+ write build/startup-sequence S/startup-sequence + write build/exp4

run: build/exp4.adf
	$(UAE) --floppy_drive_0=$(CURDIR)/build/exp4.adf

clean:
	rm -rf build

FORCE:
.PHONY: all run clean FORCE

$(STARS): tools/make_stars.py
	@mkdir -p build
	python3 tools/make_stars.py $@
