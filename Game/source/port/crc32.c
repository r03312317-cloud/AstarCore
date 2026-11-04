// [ARCH] CRC32 用于数据内容与装载链路的完整性校验。
// [ARCH] 校验范围由地址和长度共同定义。
// [ARCH] 它用于检测错误，不提供密码学身份认证。
// [ARCH] 主机装载还需要接收校验和目标内存回读都通过。
#include "soc_port.h"
uint32_t soc_crc32(const void *data,size_t length) {
    static uint32_t table[256];static int ready;
    if(!ready){for(unsigned i=0;i<256;i++){uint32_t c=i;for(unsigned j=0;j<8;j++)c=(c>>1)^(0xedb88320u&-(c&1u));table[i]=c;}ready=1;}
    const uint8_t *p=data;uint32_t crc=0xffffffffu;
    while(length--)crc=(crc>>8)^table[(crc^*p++)&255u];
    return ~crc;
}
