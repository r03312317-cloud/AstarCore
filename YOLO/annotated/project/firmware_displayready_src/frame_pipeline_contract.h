// 架构导读：frame_pipeline_contract。
// 片上存储器数据路径，保存地址、读写使能以及同步读返回状态。
#ifndef SOC_FRAME_PIPELINE_CONTRACT_H
#define SOC_FRAME_PIPELINE_CONTRACT_H
/* CPU-side no-alias proof for the Graph204 shared-input lease. The graph
 * executor still performs its own complete parameter/layout validation.
 * This additional proof must complete BEFORE next-camera capture is armed.
 * No untrusted graph operation may touch the two raw frames, FB pair, or
 * the 320x320 input after Conv0 has retired.
 */
#define CMOS2_GRAPH_CEILING 0x81000000u
#define CMOS2_INPUT_SIZE SOC_PP320_TARGET_BYTES
// 服务函数 cmos2_graph_region。
// 接口参数：uint32_t address,uint32_t bytes,uint32_t input,；返回值及副作用由下列函数体定义。
// 参数入口：address, bytes, first_input；类型、指针限定及返回约定沿用下列声明。
static int cmos2_graph_region(uint32_t address,uint32_t bytes,uint32_t input,
                              uint32_t first_input) {
    // 控制边界：!range(address,bytes)||address>=CMOS2_GRAPH_CEILING ||；仅在该条件成立时进入本分支。
    if(!range(address,bytes)||address>=CMOS2_GRAPH_CEILING ||
       bytes>CMOS2_GRAPH_CEILING-address)return 0;
    // 控制边界：overlap(address,bytes,input,CMOS2_INPUT_SIZE) &&；仅在该条件成立时进入本分支。
    if(overlap(address,bytes,input,CMOS2_INPUT_SIZE) &&
       !(first_input && address==input && bytes==CMOS2_INPUT_SIZE))return 0;
    return 1;
}
// 服务函数 cmos2_graph_input_lifetime。
// 接口参数：const uint32_t c[WORKFLOW_WORDS]；返回值及副作用由下列函数体定义。
// 参数入口：WORKFLOW_WORDS；类型、指针限定及返回约定沿用下列声明。
static int cmos2_graph_input_lifetime(const uint32_t c[WORKFLOW_WORDS]) {
    const uint32_t input=c[3];
    // 控制边界：input!=0x80100000u || !cmos2_graph_region(c[6],204u*96u,input,0u) ||；仅在该条件成立时进入本分支。
    if(input!=0x80100000u || !cmos2_graph_region(c[6],204u*96u,input,0u) ||
       !cmos2_graph_region(c[7],204u*24u,input,0u) ||
       !cmos2_graph_region(c[8],c[9],input,0u) ||
       !cmos2_graph_region(c[10],96u,input,0u) ||
       !cmos2_graph_region(c[11],c[17]*sizeof(soc_detection),input,0u) ||
       !cmos2_graph_region(c[12],c[16]*sizeof(soc_detection),input,0u))return 0;
    for(uint32_t i=0;i<GRAPH_MAX_OPS;i++) {
        uint32_t d[GRAPH_WORDS_PER_OP];
        uint32_t base=c[6]+i*GRAPH_WORDS_PER_OP*4u;
        for(uint32_t j=0;j<GRAPH_WORDS_PER_OP;j++)d[j]=R32(base+j*4u);
        // 控制边界：d[3] || (d[0]==10u?d[2]!=72u:d[0]==11u?d[2]!=40u:d[0]==12u?d[2]!=64u:1)；仅在该条件成立时进入本分支。
        if(d[3] || (d[0]==10u?d[2]!=72u:d[0]==11u?d[2]!=40u:d[0]==12u?d[2]!=64u:1))return 0;
        // 控制边界：i==0 && (d[0]!=10u || d[1]!=input)；仅在该条件成立时进入本分支。
        if(i==0 && (d[0]!=10u || d[1]!=input))return 0;
        // 控制边界：d[0]==10u；仅在该条件成立时进入本分支。
        if(d[0]==10u) {
            soc_conv2d_shape sh={d[7],d[8],d[9],d[10],d[11],d[12],
                                    d[13],d[14],d[15],d[16],d[17],d[18],
                                    d[19],d[20],d[21]};
            soc_conv2d_layout l;
            uint32_t stride,scratch;
            // 控制边界：!soc_conv2d_layout_int8_i32(&sh,&l) ||；仅在该条件成立时进入本分支。
            if(!soc_conv2d_layout_int8_i32(&sh,&l) ||
               !soc_conv2d_workspace_bytes(&sh,&l,&stride,&scratch) ||
               !cmos2_graph_region(d[1],l.input_bytes,input,i==0u) ||
               !cmos2_graph_region(d[4],l.weight_bytes,input,0u) ||
               !cmos2_graph_region(d[5],l.output_bytes,input,0u) ||
               (scratch&&!cmos2_graph_region(d[6],scratch,input,0u)))return 0;
        } else if(d[0]==11u) {
            uint32_t n=d[8],channels=d[9];
            if(!n || !channels || n%channels || n>0x02000000u ||
               channels>0x02000000u ||
               !cmos2_graph_region(d[1],n*4u,input,0u) ||
               !cmos2_graph_region(d[4],n,input,0u) ||
               !cmos2_graph_region(d[5],channels*4u,input,0u) ||
               !cmos2_graph_region(d[6],channels*4u,input,0u) ||
               !cmos2_graph_region(d[7],channels*4u,input,0u))return 0;
        } else {
            soc_tensor_shape sh={d[6],d[7],d[8],d[9],d[10],d[11],
                                    d[12],d[13],d[14],d[15],d[16],d[17],
                                    d[18],d[19]};
            soc_tensor_layout l;
            if(!soc_tensor_layout_int8(&sh,&l) ||
               !cmos2_graph_region(d[1],l.input_bytes,input,0u) ||
               !cmos2_graph_region(d[4],l.output_bytes,input,0u) ||
               (l.aux_bytes && !cmos2_graph_region(d[5],l.aux_bytes,input,0u)))return 0;
        }
    }
    /* NMS operates during camera prefetch. Its three head descriptors also
     * contain DDR pointers, so proving the descriptor table alone is NOT
     * sufficient: prove the head tensors, anchors and sigmoid table ranges. */
    for(uint32_t i=0u;i<3u;i++) {
        uint32_t h=c[10]+i*32u;
        // 硬件/可见性边界：uint32_t tensor=R32(h),w=R32(h+4u),height=R32(h+8u);。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        uint32_t tensor=R32(h),w=R32(h+4u),height=R32(h+8u);
        // 硬件/可见性边界：uint32_t anchor=R32(h+16u),sigmoid=R32(h+20u);。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        uint32_t anchor=R32(h+16u),sigmoid=R32(h+20u);
        uint64_t bytes=(uint64_t)w*height*3u*(c[13]+5u);
        if(!w||w>2048u||!height||height>2048u||bytes>0xffffffffu ||
           // 硬件/可见性边界：R32(h+24u)||R32(h+28u)||。
           // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
           R32(h+24u)||R32(h+28u)||
           !cmos2_graph_region(tensor,(uint32_t)bytes,input,0u) ||
           !cmos2_graph_region(anchor,12u,input,0u) ||
           !cmos2_graph_region(sigmoid,512u,input,0u))return 0;
    }
    return 1;
}
#endif
