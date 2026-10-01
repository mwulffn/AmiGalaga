# experiment-1: bob stress test for a stock A500
NBOBS ?= 50
DEFS  ?=
ROM   ?= ../original/galaga.zip
KICK  ?= $(HOME)/Documents/FS-UAE/Kickstarts/kick34005.A500
UAE    = fs-uae --amiga_model=A500 --kickstart_file=$(KICK) --slow_memory=0

GFX = build/enemies.bin build/sprites.bin build/gfx.i

all: build/exp1.adf

$(GFX) &: tools/extract_gfx.py $(ROM)
	@mkdir -p build
	python3 tools/extract_gfx.py $(ROM) build

build/exp1: src/main.s src/measure.i $(GFX) FORCE
	vasmm68k_mot -quiet -Fhunkexe -kick1hunks -nosym -DNBOBS=$(NBOBS) $(DEFS) \
		-Ibuild -Isrc -o $@ src/main.s

build/exp1.adf: build/exp1
	@printf 'exp1\n' > build/startup-sequence
	xdftool $@ format exp1 + boot install + makedir S \
		+ write build/startup-sequence S/startup-sequence + write build/exp1

run: build/exp1.adf
	$(UAE) --floppy_drive_0=$(CURDIR)/build/exp1.adf

clean:
	rm -rf build

FORCE:
.PHONY: all run clean FORCE
