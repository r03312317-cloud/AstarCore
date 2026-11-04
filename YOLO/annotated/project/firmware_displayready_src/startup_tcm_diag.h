/* Diagnostic candidate only. No model/DDR/camera writes, and no per-frame work.
 * The host must compare both rodata CRCs with the exact linked normal image.
 * Equality between two board CRCs alone does not establish the image is intact.
 */
// 架构导读：startup_tcm_diag。
// 在正常固件启动时检查片上程序/只读数据的完整性。
static uint32_t boot_tcm_fault;
#ifdef BOARD_HOST_UNIT
/* Native guard tests never run the physical monitor's boot entry. */
static void startup_tcm_diagnostics(void) { boot_tcm_fault=0; }
#else
extern uint8_t __rodata_start[],__rodata_end[];
static volatile uint32_t boot_tcm_scratch[64] __attribute__((aligned(32)));

// 服务函数 boot_crc_byte。
// 接口参数：uint32_t crc,uint8_t value；返回值及副作用由下列函数体定义。
// 参数入口：crc, value；类型、指针限定及返回约定沿用下列声明。
static uint32_t boot_crc_byte(uint32_t crc,uint8_t value) {
    crc^=value;
    for(unsigned i=0;i<8;i++)crc=(crc>>1)^((0u-(crc&1u))&0xedb88320u);
    return crc;
}
// 服务函数 boot_hex。
// 接口参数：uint32_t value；返回值及副作用由下列函数体定义。
// 参数入口：value；类型、指针限定及返回约定沿用下列声明。
static void boot_hex(uint32_t value) {
    /* Digit generation uses arithmetic, not a possibly damaged DTCM LUT. */
    for(int shift=28;shift>=0;shift-=4) {
        uint32_t n=(value>>(unsigned)shift)&15u;
        tx((uint8_t)(n<10u?'0'+n:'a'+n-10u));
    }
}
// 服务函数 boot_word_pattern。
// 接口参数：unsigned i；返回值及副作用由下列函数体定义。
// 参数入口：i；类型、指针限定及返回约定沿用下列声明。
static uint32_t boot_word_pattern(unsigned i) {
    return 0xa5a5a5a5u^((uint32_t)i*0x01020408u);
}
// 服务函数 startup_tcm_diagnostics。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static void startup_tcm_diagnostics(void) {
    uintptr_t begin=(uintptr_t)__rodata_start,end=(uintptr_t)__rodata_end;
    uint32_t byte_crc=0xffffffffu,word_crc=0xffffffffu,table_crc=0xffffffffu;
    uint32_t words_bad=0,bytes_bad=0,first=0xffffffffu,want_first=0,got_first=0;
    for(uintptr_t p=begin;p<end;p++)byte_crc=boot_crc_byte(byte_crc,R8(p));
    for(uintptr_t p=begin;p<end;p+=4u) {
        // 硬件/可见性边界：uint32_t value=R32(p);。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        uint32_t value=R32(p);
        for(unsigned lane=0;lane<4&&p+lane<end;lane++)
            word_crc=boot_crc_byte(word_crc,(uint8_t)(value>>(8u*lane)));
    }
    for(unsigned i=0;i<256;i++) {
        uint32_t value=*(volatile uint32_t *)(crc_table+i);
        for(unsigned lane=0;lane<4;lane++)table_crc=boot_crc_byte(table_crc,(uint8_t)(value>>(8u*lane)));
    }
    for(unsigned i=0;i<64;i++)boot_tcm_scratch[i]=boot_word_pattern(i);
    // 硬件/可见性边界：fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();
    for(unsigned i=0;i<64;i++) {
        uint32_t want=boot_word_pattern(i),got=boot_tcm_scratch[i];
        // 控制边界：got!=want；仅在该条件成立时进入本分支。
        if(got!=want) {
            words_bad++;
            if(first==0xffffffffu){first=i;want_first=want;got_first=got;}
        }
        for(unsigned lane=0;lane<4;lane++)
            if(*((volatile uint8_t *)(boot_tcm_scratch+i)+lane)!=(uint8_t)(want>>(8u*lane)))bytes_bad++;
    }
    for(unsigned lane=0;lane<4;lane++) {
        for(unsigned i=0;i<64;i++) {
            uint32_t mask=255u<<(8u*lane),want=boot_word_pattern(i);
            boot_tcm_scratch[i]=want;
            uint8_t value=(uint8_t)(i*13u+lane*17u+7u);
            *((volatile uint8_t *)(boot_tcm_scratch+i)+lane)=value;
            // 硬件/可见性边界：fence_all();want=(want&~mask)|((uint32_t)value<<(8u*lane));。
            // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
            fence_all();want=(want&~mask)|((uint32_t)value<<(8u*lane));
            uint32_t got=boot_tcm_scratch[i];
            if(got!=want){words_bad++;if(first==0xffffffffu){first=i;want_first=want;got_first=got;}}
            if(*((volatile uint8_t *)(boot_tcm_scratch+i)+lane)!=value)bytes_bad++;
        }
    }
    for(unsigned i=0;i<64;i++)boot_tcm_scratch[i]=0;
    // 硬件/可见性边界：fence_all();byte_crc^=0xffffffffu;word_crc^=0xffffffffu;table_crc^=0xffffffffu;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();byte_crc^=0xffffffffu;word_crc^=0xffffffffu;table_crc^=0xffffffffu;
    boot_tcm_fault=(words_bad||bytes_bad||byte_crc!=word_crc||table_crc!=0x6fcf9e13u);
    text("SOC_TCM_DIAG v=1 build=" BOARD_BUILD_ID " rodata_bytes=");boot_hex((uint32_t)(end-begin));
    text(" byte_crc=");boot_hex(byte_crc);text(" word_crc=");boot_hex(word_crc);
    text(" table_crc=");boot_hex(table_crc);text(" word_err=");boot_hex(words_bad);
    text(" byte_err=");boot_hex(bytes_bad);text(" first_word=");boot_hex(first);
    text(" want=");boot_hex(want_first);text(" got=");boot_hex(got_first);
    text(" fault=");boot_hex(boot_tcm_fault);text("\r\n");
}
#endif
