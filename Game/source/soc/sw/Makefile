# ---------------------------------------------------------------------------
# rv32_soc_Game firmware
#
#   make device   RISC-V ELF + ITCM/DTCM init files for the FPGA bitstream
#   make host     PC build of the same game for automated playthrough
#   make all      both
#
# The RISC-V toolchain is the one already used by the mainline project
# (xPack riscv-none-elf-gcc 15.2.0).  Override CROSS to use another one.
# ---------------------------------------------------------------------------
CROSS   ?= $(HOME)/AppData/Roaming/xPacks/riscv-none-elf-gcc/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-
HOSTCC  ?= C:/Users/user/mingw64/bin/gcc.exe
PYTHON  ?= python

BUILD   := ../build/sw
DEV     := $(BUILD)/device
HOST    := $(BUILD)/host

# zicsr is needed for the mtvec/mcause accesses in common/start.S; binutils 2.4x
# no longer implies it from rv32im.  The core implements the machine CSRs.
ARCH    := -march=rv32im_zicsr -mabi=ilp32 -mcmodel=medlow -msmall-data-limit=0
CFLAGS  := $(ARCH) -O2 -ffreestanding -fno-builtin -fno-common -nostdlib \
           -Wall -Wextra -Wno-unused-parameter -Iinclude -Igame
LDFLAGS := $(ARCH) -T common/link.ld -nostdlib -nostartfiles \
           -Wl,--gc-sections -Wl,--no-relax

DEV_SRC := common/start.S \
           game/main.c game/game_logic.c game/game_render.c game/game_assets.c \
           platform/soc/soc_platform.c

HOST_SRC := game/game_logic.c game/game_render.c game/game_assets.c \
            platform/host/host_platform.c platform/host/host_main.c

.PHONY: all device host clean assets

all: device host

assets:
	$(PYTHON) tools/make_assets.py

device: $(DEV)/game.elf $(DEV)/game-itcm.mem $(DEV)/game-dtcm.mem

$(DEV)/game.elf: $(DEV_SRC) include/game.h include/game_hal.h include/game_regs.h \
                 game/game_assets.h common/link.ld | $(DEV)
	$(CROSS)gcc $(CFLAGS) $(DEV_SRC) $(LDFLAGS) -o $@
	$(CROSS)size $@

$(DEV)/game-itcm.mem: $(DEV)/game.elf tools/elf2mem.py
	$(PYTHON) tools/elf2mem.py $(DEV)/game.elf $(DEV)/game-itcm.mem $(DEV)/game-dtcm.mem
	@ls -l $(DEV)/game-itcm.mem $(DEV)/game-dtcm.mem

$(DEV)/game-dtcm.mem: $(DEV)/game-itcm.mem
	@true

host: $(HOST)/game_host.exe

$(HOST)/game_host.exe: $(HOST_SRC) include/game.h include/game_hal.h game/game_assets.h | $(HOST)
	$(HOSTCC) -O2 -std=gnu11 -Wall -Wextra -Wno-unused-parameter -Iinclude -Igame \
		$(HOST_SRC) -o $@

$(DEV) $(HOST):
	@mkdir -p $@

clean:
	rm -rf $(BUILD)
