// 架构导读：memory_helpers。
// 为裸机固件提供内存复制、填充等基础例程。
#include <stddef.h>
#include <stdint.h>
/* Freestanding GCC may lower stack aggregate initialization to memset. */
void *memset(void *destination,int value,size_t length) {
    volatile uint8_t *out=(volatile uint8_t *)destination;
    for(size_t i=0;i<length;i++)out[i]=(uint8_t)value;
    return destination;
}
/* RISC-V freestanding GCC is allowed to expand structure copies to memcpy.
 * Do not depend on a hosted libc when linking the 64 KiB TCM firmware. */
void *memcpy(void *destination,const void *source,size_t length) {
    volatile uint8_t *out=(volatile uint8_t *)destination;
    const volatile uint8_t *in=(const volatile uint8_t *)source;
    for(size_t i=0;i<length;i++)out[i]=in[i];
    return destination;
}
