#ifndef SOC_CAMERA_SCCB_READBACK_H
#define SOC_CAMERA_SCCB_READBACK_H
/* CPU-owned bounded diagnostics. Each bit drives low or releases the pin.
 * The physical return levels are synchronized by the board MMIO unit. */
#ifndef SCB_READ
#define SCB_READ(offset) R32(CAMERA+(offset))
#define SCB_WRITE(offset,value) do { R32(CAMERA+(offset))=(value); fence_all(); } while(0)
#define SCB_DELAY() do { uint32_t t=ticks(); while((uint32_t)(ticks()-t)<HZ/100000u) {} } while(0)
#define SCB_TICKS() ticks()
#define SCB_TIMEOUT_TICKS (HZ/500u)
#endif
typedef struct { uint32_t channel,control,error,acks; } scb_context;
enum { SCB_OK,SCB_BUS_NOT_IDLE,SCB_CLOCK_TIMEOUT,SCB_WRITE_ADDR_NACK,
       SCB_REG_HIGH_NACK,SCB_REG_LOW_NACK,SCB_READ_ADDR_NACK,SCB_STOP_ERROR };
static void scb_lines(scb_context *c,uint32_t scl_low,uint32_t sda_low) {
    c->control=(1u<<c->channel) | (scl_low<<(2u+2u*c->channel)) |
               (sda_low<<(3u+2u*c->channel));
    SCB_WRITE(0x60u,c->control);SCB_DELAY();
}
static uint32_t scb_levels(const scb_context *c) {
    return (SCB_READ(0x68u)>>(2u*c->channel))&3u;
}
static int scb_clock_high(scb_context *c) {
    uint32_t started=SCB_TICKS();
    while(!(scb_levels(c)&1u)) {
        if((uint32_t)(SCB_TICKS()-started)>SCB_TIMEOUT_TICKS) {
            c->error=SCB_CLOCK_TIMEOUT;return 0;
        }
    }
    return 1;
}
static int scb_start(scb_context *c) {
    scb_lines(c,0,0);
    if(!scb_clock_high(c))return 0;
    if(!(scb_levels(c)&2u)){c->error=SCB_BUS_NOT_IDLE;return 0;}
    scb_lines(c,0,1);scb_lines(c,1,1);return 1;
}
static int scb_stop(scb_context *c) {
    scb_lines(c,1,1);scb_lines(c,0,1);
    if(!scb_clock_high(c)){scb_lines(c,0,0);return 0;}
    scb_lines(c,0,0);
    if(scb_levels(c)!=3u){if(!c->error)c->error=SCB_STOP_ERROR;return 0;}
    return 1;
}
static int scb_send(scb_context *c,uint8_t value,uint32_t stage) {
    for(unsigned i=0;i<8;i++) {
        uint32_t low=!(value&(0x80u>>i));
        scb_lines(c,1,low);scb_lines(c,0,low);
        if(!scb_clock_high(c))return 0;
        scb_lines(c,1,low);
    }
    scb_lines(c,1,0);scb_lines(c,0,0);
    if(!scb_clock_high(c))return 0;
    uint32_t ack=!(scb_levels(c)&2u);
    scb_lines(c,1,0);
    if(!ack){c->error=stage;return 0;}
    c->acks|=1u<<(stage-SCB_WRITE_ADDR_NACK);return 1;
}
static int scb_receive(scb_context *c,uint8_t *value) {
    uint8_t result=0;
    for(unsigned i=0;i<8;i++) {
        scb_lines(c,1,0);scb_lines(c,0,0);
        if(!scb_clock_high(c))return 0;
        result=(uint8_t)((result<<1)|((scb_levels(c)>>1)&1u));
        scb_lines(c,1,0);
    }
    /* Single-byte read ends with master NACK: SDA remains released. */
    scb_lines(c,0,0);if(!scb_clock_high(c))return 0;
    scb_lines(c,1,0);*value=result;return 1;
}
static uint32_t scb_read_register(scb_context *c,uint16_t address,uint8_t *value) {
    c->error=0;c->acks=0;*value=0xff;
    if(scb_start(c) && scb_send(c,0x78,SCB_WRITE_ADDR_NACK) &&
       scb_send(c,(uint8_t)(address>>8),SCB_REG_HIGH_NACK) &&
       scb_send(c,(uint8_t)address,SCB_REG_LOW_NACK) && scb_stop(c) &&
       scb_start(c) && scb_send(c,0x79,SCB_READ_ADDR_NACK))
        (void)scb_receive(c,value);
    (void)scb_stop(c);
    return c->error;
}
#endif
