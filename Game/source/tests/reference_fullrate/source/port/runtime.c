#include "mario_port.h"
#include "fce.h"
#include "ppu.h"
#include "psg.h"
#include "cpu-internal.h"
#include "soc_port.h"
#include <string.h>
extern const unsigned char rom_mario_nes[];
extern const unsigned int rom_mario_nes_len;
static unsigned frames;
int mario_boot(void) {
    const unsigned char *r=rom_mario_nes;
    /* This port intentionally accepts the bundled NROM-256/8KiB CHR fixture.
     * The upstream mapper 3 path has only one CHR slot and is not enabled. */
    if(rom_mario_nes_len!=40976||memcmp(r,"NES\032",4)||r[4]!=2||r[5]!=1||
       (r[6]&0xfe)||r[7])return -1;
    if(fce_load_rom((char *)(uintptr_t)r))return -2;
    fce_init();psg_init();frames=0;return 0;
}
void mario_step(void){for(unsigned scanline=0;scanline<262;scanline++){ppu_cycle();psg_detect_key();}frames++;}
unsigned mario_frame(void){return frames;}
uint32_t mario_state_crc(void){return soc_crc32(CPU_RAM,0x800);}
