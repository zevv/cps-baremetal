
NAME = main

BIN  = $(NAME).elf
FHEX := $(NAME)-flash.ihx
EHEX := $(NAME)-eeprom.ihx

NSRCS += main.nim

NIMFLAGS += --mm:arc
NIMFLAGS += --cpu:avr
NIMFLAGS += --os:any
NIMFLAGS += --opt:size
NIMFLAGS += --exceptions:goto
NIMFLAGS += --listCmd
NIMFLAGS += --stacktrace:off

NIMFLAGS += --passC:-DF_CPU=16000000UL
NIMFLAGS += --passC:-mmcu=atmega328p
NIMFLAGS += --passC:-flto

NIMFLAGS += --passL:-mmcu=atmega328p
NIMFLAGS += --passL:-flto
NIMFLAGS += --path:~/sandbox/prjs/cps

NIMFLAGS += -d:danger
NIMFLAGS += -d:noSignalHandler
NIMFLAGS += -d:danger
NIMFLAGS += -d:usemalloc

ADFLAGS += -p m328p -c avrispv2 -P usb


$(BIN): $(NSRCS)
	nim c -f $(NIMFLAGS) --out:$(BIN) $(NSRCS)

$(FHEX) $(EHEX): $(BIN)
	objcopy -j .text -j .data -O ihex $(BIN) $(FHEX)
	objcopy -j .eeprom --change-section-lma .eeprom=0 -O ihex $(BIN) $(EHEX)

install: $(FHEX) $(EHEX)
	avrdude $(ADFLAGS) -e -V -U flash:w:$(FHEX):i -U eeprom:w:$(EHEX):i


clean:
	rm -f $(BIN)
