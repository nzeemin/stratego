# Stratego for UKNC (Elektronika MS 0511) - PDP-11 GCC toolchain.
#
#   make            build build/STRATE.SAV (+ STRATE.ELF for gdb)
#   make clean
#
# UKNC = toolchain root (contains gcc/bin). Override: make UKNC=/path/to/uknc
# Works with GNU make on Windows (cmd or sh), Linux and macOS.

ifeq ($(OS),Windows_NT)
  UKNC  ?= $(LOCALAPPDATA)/Programs/UKNC
  PSEP  := ;
else
  UKNC  ?= $(HOME)/uknc
  PSEP  := :
endif

export PATH := $(UKNC)/gcc/bin$(PSEP)$(CURDIR)/tools$(PSEP)$(PATH)

CROSS   := pdp11-uknc-rt11-
MACRO11 := macro11
CC      := $(CROSS)gcc
SIZE    := $(CROSS)size

CORE    := core
BUILD   := build
# RT-11 file names are 6.3, so the image can go straight onto a disk.
TARGET  := STRATE

# Same optimisation as the z88dk build (-O2, no HARNESS, no AI_TRACE); the
# rest is what this toolchain needs to be able to drop unused functions.
CFLAGS  := -std=gnu23 -O2 -fomit-frame-pointer -ffunction-sections -fdata-sections -Wall -I$(CORE)
LDFLAGS := -nostartfiles -Wl,--gc-sections -Wl,-e,START -Wl,--no-warn-rwx-segments

CORE_SRC := state rng game ai
OBJS     := $(BUILD)/STRAT1.OBJ $(BUILD)/layout.o $(BUILD)/stack.o $(CORE_SRC:%=$(BUILD)/%.o)

all: $(BUILD)/$(TARGET).SAV $(BUILD)/$(TARGET).ELF
	$(SIZE) $(BUILD)/$(TARGET).ELF

$(BUILD)/$(TARGET).SAV: $(OBJS)
	$(CC) $(LDFLAGS) -Wl,-Map=$@.map -o $@ $(OBJS) api.ld -lgcc

$(BUILD)/$(TARGET).ELF: $(OBJS)
	$(CC) $(LDFLAGS) -Wl,-m,pdp11rt11 -o $@ $(OBJS) api.ld -lgcc

$(BUILD)/%.o: $(CORE)/%.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

# Compile-time check that core.inc offsets match the C struct layout.
$(BUILD)/stack.o: stack.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/layout.o: layout.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

# MACRO-11: -rt11 selects the RT-11 OBJ format that ld reads.
$(BUILD)/STRAT1.OBJ: STRAT1.MAC STCORE.MAC INTROSC.MAC | $(BUILD)
	$(MACRO11) -rt11 -I . -o $@ -l $(BUILD)/STRAT1.lst $<

$(BUILD):
	$(MKDIR)

ifeq ($(OS),Windows_NT)
  MKDIR := -@if not exist "$(BUILD)" mkdir "$(BUILD)"
  RMDIR := -@if exist "$(BUILD)" rmdir /s /q "$(BUILD)"
else
  MKDIR := @mkdir -p $(BUILD)
  RMDIR := @rm -rf $(BUILD)
endif

clean:
	$(RMDIR)

.PHONY: all clean

# INTROSC.MAC is generated from INTRO.TXT (needs Python); it is committed, so a
# normal build does not run this.  Run `make intro` after editing INTRO.TXT.
intro:
	python tools/mkintro.py INTRO.TXT INTROSC.MAC

.PHONY: intro
