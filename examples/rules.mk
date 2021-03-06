# ---------------------------------------
# Common make rules for all examples
# ---------------------------------------

ifeq ($(FAMILY),esp32s2)
# Espressif IDF use CMake build system, this add wrapper target to call idf.py

.PHONY: all clean flash
.DEFAULT_GOAL := all

all:
	idf.py -B$(BUILD) -DFAMILY=$(FAMILY) -DBOARD=$(BOARD) build

build: all

clean:
	idf.py -B$(BUILD) -DFAMILY=$(FAMILY) -DBOARD=$(BOARD) clean

fullclean:
	idf.py -B$(BUILD) -DFAMILY=$(FAMILY) -DBOARD=$(BOARD) fullclean

flash:
	idf.py -B$(BUILD) -DFAMILY=$(FAMILY) -DBOARD=$(BOARD) flash

bootloader-flash:
	idf.py -B$(BUILD) -DFAMILY=$(FAMILY) -DBOARD=$(BOARD) bootloader-flash

app-flash:
	idf.py -B$(BUILD) -DFAMILY=$(FAMILY) -DBOARD=$(BOARD) app-flash

erase:
	idf.py -B$(BUILD) -DFAMILY=$(FAMILY) -DBOARD=$(BOARD) erase_flash

monitor:
	idf.py -B$(BUILD) -DFAMILY=$(FAMILY) -DBOARD=$(BOARD) monitor

else ifeq ($(FAMILY),rp2040)

all:
	[ -d $(BUILD) ] || cmake -S . -B $(BUILD) -DFAMILY=$(FAMILY) -DBOARD=$(BOARD) -DPICO_BUILD_DOCS=0
	$(MAKE) -C $(BUILD)

clean:
	$(RM) -rf $(BUILD)

else
# GNU Make build system

# libc
LIBS += -lgcc -lm -lnosys

ifneq ($(BOARD), spresense)
LIBS += -lc
endif

# TinyUSB Stack source
SRC_C += \
	src/tusb.c \
	src/common/tusb_fifo.c \
	src/device/usbd.c \
	src/device/usbd_control.c \
	src/class/audio/audio_device.c \
	src/class/cdc/cdc_device.c \
	src/class/dfu/dfu_rt_device.c \
	src/class/hid/hid_device.c \
	src/class/midi/midi_device.c \
	src/class/msc/msc_device.c \
	src/class/net/net_device.c \
	src/class/usbtmc/usbtmc_device.c \
	src/class/vendor/vendor_device.c \
	src/portable/$(VENDOR)/$(CHIP_FAMILY)/dcd_$(CHIP_FAMILY).c

# TinyUSB stack include
INC += $(TOP)/src

CFLAGS += $(addprefix -I,$(INC))

# TODO Skip nanolib for MSP430
ifeq ($(BOARD), msp_exp430f5529lp)
  LDFLAGS += $(CFLAGS) -fshort-enums -Wl,-T,$(TOP)/$(LD_FILE) -Wl,-Map=$@.map -Wl,-cref -Wl,-gc-sections
else
  LDFLAGS += $(CFLAGS) -fshort-enums -Wl,-T,$(TOP)/$(LD_FILE) -Wl,-Map=$@.map -Wl,-cref -Wl,-gc-sections -specs=nosys.specs -specs=nano.specs
endif
ASFLAGS += $(CFLAGS)

# Assembly files can be name with upper case .S, convert it to .s
SRC_S := $(SRC_S:.S=.s)

# Due to GCC LTO bug https://bugs.launchpad.net/gcc-arm-embedded/+bug/1747966
# assembly file should be placed first in linking order
OBJ += $(addprefix $(BUILD)/obj/, $(SRC_S:.s=.o))
OBJ += $(addprefix $(BUILD)/obj/, $(SRC_C:.c=.o))

# Verbose mode
ifeq ("$(V)","1")
$(info CFLAGS  $(CFLAGS) ) $(info )
$(info LDFLAGS $(LDFLAGS)) $(info )
$(info ASFLAGS $(ASFLAGS)) $(info )
endif

# Set all as default goal
.DEFAULT_GOAL := all
all: $(BUILD)/$(BOARD)-firmware.bin $(BUILD)/$(BOARD)-firmware.hex size

uf2: $(BUILD)/$(BOARD)-firmware.uf2

OBJ_DIRS = $(sort $(dir $(OBJ)))
$(OBJ): | $(OBJ_DIRS)
$(OBJ_DIRS):
ifeq ($(CMDEXE),1)
	@$(MKDIR) $(subst /,\,$@)
else
	@$(MKDIR) -p $@
endif

$(BUILD)/$(BOARD)-firmware.elf: $(OBJ)
	@echo LINK $@
	@$(CC) -o $@ $(LDFLAGS) $^ -Wl,--start-group $(LIBS) -Wl,--end-group

$(BUILD)/$(BOARD)-firmware.bin: $(BUILD)/$(BOARD)-firmware.elf
	@echo CREATE $@
	@$(OBJCOPY) -O binary $^ $@

$(BUILD)/$(BOARD)-firmware.hex: $(BUILD)/$(BOARD)-firmware.elf
	@echo CREATE $@
	@$(OBJCOPY) -O ihex $^ $@

UF2_FAMILY ?= 0x00
$(BUILD)/$(BOARD)-firmware.uf2: $(BUILD)/$(BOARD)-firmware.hex
	@echo CREATE $@
	$(PYTHON) $(TOP)/tools/uf2/utils/uf2conv.py -f $(UF2_FAMILY) -c -o $@ $^

# We set vpath to point to the top of the tree so that the source files
# can be located. By following this scheme, it allows a single build rule
# to be used to compile all .c files.
vpath %.c . $(TOP)
$(BUILD)/obj/%.o: %.c
	@echo CC $(notdir $@)
	@$(CC) $(CFLAGS) -c -MD -o $@ $<

# ASM sources lower case .s
vpath %.s . $(TOP)
$(BUILD)/obj/%.o: %.s
	@echo AS $(notdir $@)
	@$(CC) -x assembler-with-cpp $(ASFLAGS) -c -o $@ $<

# ASM sources upper case .S
vpath %.S . $(TOP)
$(BUILD)/obj/%.o: %.S
	@echo AS $(notdir $@)
	@$(CC) -x assembler-with-cpp $(ASFLAGS) -c -o $@ $<

size: $(BUILD)/$(BOARD)-firmware.elf
	-@echo ''
	@$(SIZE) $<
	-@echo ''

.PHONY: clean
clean:
ifeq ($(CMDEXE),1)
	rd /S /Q $(subst /,\,$(BUILD))
else
	$(RM) -rf $(BUILD)
endif

# Print out the value of a make variable.
# https://stackoverflow.com/questions/16467718/how-to-print-out-a-variable-in-makefile
print-%:
	@echo $* = $($*)

# Flash binary using Jlink
ifeq ($(OS),Windows_NT)
  JLINKEXE = JLink.exe
else
  JLINKEXE = JLinkExe
endif

JLINK_IF ?= swd

# Flash using jlink
flash-jlink: $(BUILD)/$(BOARD)-firmware.hex
	@echo halt > $(BUILD)/$(BOARD).jlink
	@echo r > $(BUILD)/$(BOARD).jlink
	@echo loadfile $^ >> $(BUILD)/$(BOARD).jlink
	@echo r >> $(BUILD)/$(BOARD).jlink
	@echo go >> $(BUILD)/$(BOARD).jlink
	@echo exit >> $(BUILD)/$(BOARD).jlink
	$(JLINKEXE) -device $(JLINK_DEVICE) -if $(JLINK_IF) -JTAGConf -1,-1 -speed auto -CommandFile $(BUILD)/$(BOARD).jlink

# flash STM32 MCU using stlink with STM32 Cube Programmer CLI
flash-stlink: $(BUILD)/$(BOARD)-firmware.elf
	STM32_Programmer_CLI --connect port=swd --write $< --go

# flash with pyocd
flash-pyocd: $(BUILD)/$(BOARD)-firmware.hex
	pyocd flash -t $(PYOCD_TARGET) $<
	pyocd reset -t $(PYOCD_TARGET)

endif # Make target
