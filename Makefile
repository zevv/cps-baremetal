
NAME = main
BIN  = main

NSRCS += main.nim

NIMFLAGS += --mm:arc
NIMFLAGS += --cpu:avr
NIMFLAGS += --os:any
NIMFLAGS += --opt:size
NIMFLAGS += --exceptions:goto
NIMFLAGS += --listCmd

NIMFLAGS += --passC:-DF_CPU=16000000UL
NIMFLAGS += --passC:-mmcu=atmega328p
NIMFLAGS += --passC:-flto

NIMFLAGS += --passL:-mmcu=atmega328p
NIMFLAGS += --passL:-flto

NIMFLAGS += -d:danger
NIMFLAGS += -d:noSignalHandler
NIMFLAGS += -d:danger
NIMFLAGS += -d:usemalloc



$(BIN): $(NSRCS)
	nim c -f $(NIMFLAGS) --out:$(BIN) $(NSRCS)

clean:
	rm -f $(BIN)
