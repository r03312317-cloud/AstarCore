#include "soc_port.h"
uint32_t soc_crc32(const void *data,size_t length) {
    static uint32_t table[256];static int ready;
    if(!ready){for(unsigned i=0;i<256;i++){uint32_t c=i;for(unsigned j=0;j<8;j++)c=(c>>1)^(0xedb88320u&-(c&1u));table[i]=c;}ready=1;}
    const uint8_t *p=data;uint32_t crc=0xffffffffu;
    while(length--)crc=(crc>>8)^table[(crc^*p++)&255u];
    return ~crc;
}
