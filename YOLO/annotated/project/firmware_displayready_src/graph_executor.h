// 架构导读：graph_executor。
// 将已验证的 Graph204 描述符编译为 GRAPH_EXECUTOR1 命令并提交硬件图执行。
#ifndef SOC_GRAPH_EXECUTOR_H
#define SOC_GRAPH_EXECUTOR_H
/* Compile the checked model once per ARM. Each frame uses one START; the CPU
 * never emits a Conv/S3/tensor command or polls a node on this path. */
#define GRAPH_EXECUTOR_MMIO 0x70000200u
#define GRAPH_EXECUTOR_ID 0x31585047u
#define GRAPH_EXECUTOR_PENDING 0xfffffffeu
enum {GX_END,GX_WRITE,GX_CONTEXT,GX_WAIT,GX_CHECK,GX_ACCUM,GX_BEGIN,GX_END_NODE};
static uint32_t graph_executor_words,graph_executor_crc,graph_executor_capacity,graph_executor_compile_error,graph_executor_model_epoch,graph_executor_ready;
static uint32_t graph_executor_batch_cap,graph_executor_starts,graph_executor_finishes,graph_executor_polls;
static uint64_t graph_executor_compile_ticks,graph_executor_cpu_poll_ticks;
// 服务函数 graph_executor_emit。
// 检查片上命令容量，写入四个 32 位命令字，并同步累计程序 CRC。
// 参数入口：op, a, b, c；类型、指针限定及返回约定沿用下列声明。
static void graph_executor_emit(uint32_t op,uint32_t a,uint32_t b,uint32_t c) {
    // 控制边界：graph_executor_compile_error；仅在该条件成立时进入本分支。
    if(graph_executor_compile_error)return;
    // 控制边界：graph_executor_words>graph_executor_capacity || graph_executor_capacity-graph_executor_words<4u；仅在该条件成立时进入本分支。
    if(graph_executor_words>graph_executor_capacity || graph_executor_capacity-graph_executor_words<4u){graph_executor_compile_error=GRAPH_BAD_DESCRIPTOR;return;}
    uint32_t w[4]={op,a,b,c};
    for(uint32_t i=0;i<4u;i++) {
        // 硬件/可见性边界：R32(GRAPH_EXECUTOR_MMIO+0x1cu)=w[i];graph_executor_crc=crc_bytes(graph_executor_crc,(const uint8_t *)&w[i],4u);。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        R32(GRAPH_EXECUTOR_MMIO+0x1cu)=w[i];graph_executor_crc=crc_bytes(graph_executor_crc,(const uint8_t *)&w[i],4u);
    }
    graph_executor_words+=4u;
}
// 服务函数 graph_executor_write。
// 编码一次硬件寄存器写入指令；真正的总线执行由 GRAPH_EXECUTOR1 完成。
// 参数入口：address, value；类型、指针限定及返回约定沿用下列声明。
static void graph_executor_write(uint32_t address,uint32_t value){graph_executor_emit(GX_WRITE,address,value,0u);}
// 服务函数 graph_executor_check。
// 编码寄存器掩码检查，使图指令流能校验硬件状态和预期计数。
// 参数入口：address, value, mask；类型、指针限定及返回约定沿用下列声明。
static void graph_executor_check(uint32_t address,uint32_t value,uint32_t mask){graph_executor_emit(GX_CHECK,address,value,mask);}
// 服务函数 graph_executor_accum。
// 编码性能计数累加指令，将指定硬件寄存器关联到图执行器的统计槽。
// 参数入口：address, index；类型、指针限定及返回约定沿用下列声明。
static void graph_executor_accum(uint32_t address,uint32_t index){graph_executor_emit(GX_ACCUM,address,index,0u);}
// 服务函数 graph_executor_disjoint。
// 两两检查非零长度内存区域是否重叠，避免图节点在校验阶段接受冲突缓冲。
// 参数入口：a, n, count；类型、指针限定及返回约定沿用下列声明。
static uint32_t graph_executor_disjoint(const uint32_t *a,const uint32_t *n,uint32_t count) {
    for(uint32_t i=0;i<count;i++)for(uint32_t j=i+1u;j<count;j++)
        // 控制边界：n[i]&&n[j]&&overlap(a[i],n[i],a[j],n[j])；仅在该条件成立时进入本分支。
        if(n[i]&&n[j]&&overlap(a[i],n[i],a[j],n[j]))return 0u;
    return 1u;
}
// 服务函数 graph_executor_conv。
// 校验卷积形状、低 DDR 地址及 scratch 条件，再构造卷积服务命令和预期 MAC/任务计数。
// 参数入口：index, d；类型、指针限定及返回约定沿用下列声明。
static uint32_t graph_executor_conv(uint32_t index,const uint32_t *d) {
    soc_conv2d_shape s;memcpy(&s,&d[7],sizeof(s));
    soc_conv2d_layout l;uint32_t stride,bytes;
    // 控制边界：!soc_conv2d_layout_int8_i32(&s,&l)||!soc_conv2d_workspace_bytes(&s,&l,&stride,&bytes)；仅在该条件成立时进入本分支。
    if(!soc_conv2d_layout_int8_i32(&s,&l)||!soc_conv2d_workspace_bytes(&s,&l,&stride,&bytes))return CONV_BAD_SHAPE;
    // 控制边界：(d[5]&3u)||(bytes&&(d[6]&63u))||s.tile_m!=64u||l.rows>65535u||l.k>1152u||；仅在该条件成立时进入本分支。
    if((d[5]&3u)||(bytes&&(d[6]&63u))||s.tile_m!=64u||l.rows>65535u||l.k>1152u||
       s.output_c>65535u||l.output_w>65535u||s.input_h>65535u||s.input_w>65535u||s.input_c>65535u||
       l.output_h>65535u||s.kernel_h>255u||s.kernel_w>255u||s.stride_h>255u||s.stride_w>255u||
       s.dilation_h>255u||s.dilation_w>255u||s.pad_top>255u||s.pad_left>255u||s.pad_bottom>255u||s.pad_right>255u)return CONV_BAD_SHAPE;
    const uint32_t address[4]={d[1],d[4],d[5],d[6]},length[4]={l.input_bytes,l.weight_bytes,l.output_bytes,bytes};
    // 控制边界：!graph_executor_disjoint(address,length,4u)；仅在该条件成立时进入本分支。
    if(!graph_executor_disjoint(address,length,4u))return BAD_RANGE;
    uint32_t batch=conv_service_effective_window_rows(graph_executor_batch_cap,l.k,stride,bytes!=0u);
    // 控制边界：!batch；仅在该条件成立时进入本分支。
    if(!batch)return NPU_ERROR;
    uint32_t p[31]={0};
    p[2]=l.rows;p[3]=(l.k<<16)|s.output_c;p[4]=l.output_w;p[5]=bytes?1u:0u;
    p[6]=d[1];p[7]=d[4];p[8]=d[5];p[9]=l.k;p[10]=s.output_c*4u;
    p[11]=l.k*64u;p[12]=s.output_c*256u;p[13]=l.k*8u;p[14]=d[6];p[15]=stride;
    p[20]=d[1];p[21]=d[6];p[23]=(s.input_w<<16)|s.input_h;
    p[24]=(l.output_h<<16)|s.input_c;p[25]=l.output_w;p[26]=64u<<16;
    p[27]=(s.stride_w<<24)|(s.stride_h<<16)|(s.kernel_w<<8)|s.kernel_h;
    p[28]=(s.pad_left<<24)|(s.pad_top<<16)|(s.dilation_w<<8)|s.dilation_h;
    p[29]=(s.pad_right<<8)|s.pad_bottom;
    graph_executor_emit(GX_BEGIN,index,1u,0u);
    graph_executor_check(CONV_SERVICE_MMIO+4u,0u,0x8001u);graph_executor_check(NPU+0x0cu,5u,0x47u);
    graph_executor_write(NPU+0x14u,3u);graph_executor_write(NPU+0x78u,0xfffu);
    for(uint32_t j=0;j<31u;j++) {
        // 控制边界：j<2u；仅在该条件成立时进入本分支。
        if(j<2u)graph_executor_emit(GX_CONTEXT,CONV_SERVICE_MMIO+0x40u+4u*j,j,0u);
        // 服务函数 graph_executor_write。
        // 编码一次硬件寄存器写入指令；真正的总线执行由 GRAPH_EXECUTOR1 完成。
        // 参数入口：j, j；类型、指针限定及返回约定沿用下列声明。
        else graph_executor_write(CONV_SERVICE_MMIO+0x40u+4u*j,p[j]);
    }
    graph_executor_write(CONV_SERVICE_MMIO,1u);graph_executor_emit(GX_WAIT,CONV_SERVICE_MMIO+4u,2u,0x8000u);
    graph_executor_check(CONV_SERVICE_MMIO+4u,2u,0xfffbu);
    uint64_t macs=(uint64_t)l.rows*s.output_c*l.k;
    uint32_t limit=conv_service_page_limit(l.k),pages=(s.output_c+limit-1u)/limit;
    graph_executor_check(CONV_SERVICE_MMIO+0x0cu,(uint32_t)macs,UINT32_MAX);
    graph_executor_check(CONV_SERVICE_MMIO+0x10u,(uint32_t)(macs>>32),UINT32_MAX);
    graph_executor_check(CONV_SERVICE_MMIO+0x14u,((l.rows+15u)/16u)*pages,UINT32_MAX);
    graph_executor_check(CONV_SERVICE_MMIO+0x18u,bytes?((l.rows+batch-1u)/batch)*pages:0u,UINT32_MAX);
    graph_executor_check(CONV_SERVICE_MMIO+0x24u,bytes?l.rows*l.k*pages:0u,UINT32_MAX);
    graph_executor_accum(CONV_SERVICE_MMIO+0x1cu,0u);graph_executor_accum(CONV_SERVICE_MMIO+0x3cu,1u);
    graph_executor_accum(CONV_SERVICE_MMIO+0x18u,2u);
    for(uint32_t j=0;j<7u;j++)graph_executor_accum(CONV_SERVICE_MMIO+0x20u+4u*j,3u+j);
    graph_executor_accum(CONV_SERVICE_MMIO+0x14u,31u);
    graph_executor_emit(GX_END_NODE,index,0u,bytes?2u:1u);return OK;
}
// 服务函数 graph_executor_requant。
// 从前一卷积推导数值界限，并检查可融合 LUT 节点；校验后编码 S3 寄存器序列。
// 参数入口：index, count, d, fused；类型、指针限定及返回约定沿用下列声明。
static uint32_t graph_executor_requant(uint32_t index,uint32_t count,const uint32_t *d,uint32_t *fused) {
    uint32_t bound=0u,lut=0u,target=d[4],elements=d[8],channels=d[9];
    // 控制边界：index && graph_words[index-1u][0]==10u；仅在该条件成立时进入本分支。
    if(index && graph_words[index-1u][0]==10u) {
        const uint32_t *p=graph_words[index-1u];
        soc_conv2d_shape s;memcpy(&s,&p[7],sizeof(s));
        soc_conv2d_layout l;
        // 控制边界：p[5]==d[1]&&p[10]==channels&&soc_conv2d_layout_int8_i32(&s,&l)&&；仅在该条件成立时进入本分支。
        if(p[5]==d[1]&&p[10]==channels&&soc_conv2d_layout_int8_i32(&s,&l)&&
           l.output_bytes==elements*4u&&l.k<=INT32_MAX/16384u)bound=l.k*16384u;
    }
    *fused=0u;
    // 控制边界：index+1u<count；仅在该条件成立时进入本分支。
    if(index+1u<count) {
        const uint32_t *p=graph_words[index+1u];
        // 控制边界：p[0]==12u&&p[6]==SOC_TOP_LUT&&p[1]==d[4]&&(uint64_t)p[7]*p[8]*p[9]==elements；仅在该条件成立时进入本分支。
        if(p[0]==12u&&p[6]==SOC_TOP_LUT&&p[1]==d[4]&&(uint64_t)p[7]*p[8]*p[9]==elements) {
            *fused=1u;lut=p[5];target=p[4];
        }
    }
    if(!bound||channels>256u||((d[1]|d[4]|d[5]|d[6]|d[7]|lut|target)&15u)||
       d[10]+128u>255u||d[11]+128u>255u||d[12]+128u>255u||
       (int32_t)d[11]>(int32_t)d[12]||d[13]>2u||
       !range(target,(elements+15u)&~15u)||(lut&&!range(lut,256u)))return REQUANT_BAD_PARAMS;
    const uint32_t address[6]={d[1],target,d[5],d[6],d[7],lut};
    const uint32_t length[6]={elements*4u,(elements+15u)&~15u,channels*4u,channels*4u,channels*4u,lut?256u:0u};
    if(!graph_executor_disjoint(address,length,6u))return BAD_RANGE;
    const uint32_t v[10]={d[1],target,d[5],d[6],d[7],lut,elements/channels,channels,bound,
        ((d[12]&255u)<<24)|((d[11]&255u)<<16)|((d[10]&255u)<<8)|(lut?4u:0u)|d[13]};
    graph_executor_emit(GX_BEGIN,index,2u,0u);
    for(uint32_t j=0;j<10u;j++)graph_executor_write(S3_MMIO+4u+4u*j,v[j]);
    graph_executor_write(S3_MMIO,1u);graph_executor_emit(GX_WAIT,S3_MMIO+0x2cu,2u,0xbf0u);
    graph_executor_check(S3_MMIO+0x2cu,2u,0xbf3u);
    graph_executor_check(S3_MMIO+0x34u,elements,UINT32_MAX);
    for(uint32_t j=0;j<4u;j++)graph_executor_accum(S3_MMIO+0x30u+4u*j,10u+j);
    graph_executor_emit(GX_END_NODE,index,*fused,0u);return OK;
}
// 服务函数 graph_executor_tensor。
// 检查共享张量算子的形状、对齐与缓冲分离，再编码对应硬件命令。
// 参数入口：index, d；类型、指针限定及返回约定沿用下列声明。
static uint32_t graph_executor_tensor(uint32_t index,const uint32_t *d) {
    soc_tensor_shape s;memcpy(&s,&d[6],sizeof(s));
    soc_tensor_layout l;uint32_t mode,kind;
    if(!soc_tensor_layout_int8(&s,&l)||((d[1]|d[4]|d[5]|s.input_c)&15u))return TENSOR_BAD_SHAPE;
    const uint32_t address[3]={d[1],d[4],d[5]},length[3]={l.input_bytes,l.output_bytes,l.aux_bytes};
    if(!graph_executor_disjoint(address,length,3u))return BAD_RANGE;
    if(concat_fast_supported(d[1],d[5],d[4],&s)){mode=0u;kind=3u;}
    else if(s.kind==SOC_TOP_ADD){mode=1u;kind=5u;}
    else if(s.kind==SOC_TOP_UPSAMPLE&&s.stride_h==2u&&s.stride_w==2u&&
       ((s.input_h==10u&&s.input_w==10u&&s.input_c==128u)||(s.input_h==20u&&s.input_w==20u&&s.input_c==64u))){mode=2u;kind=4u;}
    else if(s.kind==SOC_TOP_POOL&&s.input_h==10u&&s.input_w==10u&&s.input_c==128u&&
       s.kernel_h==5u&&s.kernel_w==5u&&s.stride_h==1u&&s.stride_w==1u&&
       s.pad_top==2u&&s.pad_left==2u&&s.pad_bottom==2u&&s.pad_right==2u){mode=3u;kind=6u;}
    else return TENSOR_BAD_SHAPE;
    graph_executor_emit(GX_BEGIN,index,kind,0u);
    graph_executor_emit(GX_WAIT,CONCAT_MMIO+0x1cu,1u<<17,1u<<16);
    graph_executor_check(CONCAT_MMIO+0x1cu,1u<<15,1u<<15);
    graph_executor_write(CONCAT_MMIO+0x38u,mode);graph_executor_write(CONCAT_MMIO+0x3cu,(s.input_h<<16)|s.input_w);
    const uint32_t config[6]={d[1],d[5],d[4],s.input_h*s.input_w,(s.aux_c<<16)|s.input_c,0u};
    for(uint32_t j=0;j<6u;j++)graph_executor_write(CONCAT_MMIO+4u+4u*j,config[j]);
    graph_executor_write(CONCAT_MMIO,1u);
    graph_executor_emit(GX_WAIT,CONCAT_MMIO+0x1cu,2u,0x17fe0u);
    graph_executor_check(CONCAT_MMIO+0x1cu,2u,0x17fe3u);
    graph_executor_check(CONCAT_MMIO+0x20u,l.input_bytes+l.aux_bytes,UINT32_MAX);
    graph_executor_check(CONCAT_MMIO+0x24u,l.output_bytes,UINT32_MAX);
    if(mode==0u)for(uint32_t j=0;j<4u;j++)graph_executor_accum(CONCAT_MMIO+0x20u+4u*j,14u+j);
    graph_executor_emit(GX_END_NODE,index,0u,0u);return OK;
}
// 服务函数 graph_compile_loaded。
// 接口参数：uint32_t count,uint32_t flags；返回值及副作用由下列函数体定义。
// 参数入口：count, flags；类型、指针限定及返回约定沿用下列声明。
static uint32_t graph_compile_loaded(uint32_t count,uint32_t flags) {
    const uint32_t required=GRAPH_FAST_FLAG|GRAPH_S3_FLAG|GRAPH_S3_FUSE_LUT_FLAG|GRAPH_WINDOW_FLAG|GRAPH_CONCAT_FLAG|GRAPH_PROFILE_FLAG;
    graph_executor_ready=0u;
    if(count!=GRAPH_MAX_OPS||(flags&~GRAPH_COUNT_MASK)!=required||R32(GRAPH_EXECUTOR_MMIO)!=GRAPH_EXECUTOR_ID||
       // 硬件/可见性边界：(R32(GRAPH_EXECUTOR_MMIO+4u)&9u)||conv_service_timeout_latched)return GRAPH_BAD_DESCRIPTOR;。
       // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
       (R32(GRAPH_EXECUTOR_MMIO+4u)&9u)||conv_service_timeout_latched)return GRAPH_BAD_DESCRIPTOR;
    if(R32(CONV_SERVICE_MMIO+8u)!=CONV_SERVICE_ID||R32(S3_MMIO+0x40u)!=S3_ID||
       // 硬件/可见性边界：R32(CONCAT_MMIO+0x34u)!=CONCAT_ID||R32(CONCAT_MMIO+0x40u)!=0x31534e54u)return NPU_ERROR;。
       // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
       R32(CONCAT_MMIO+0x34u)!=CONCAT_ID||R32(CONCAT_MMIO+0x40u)!=0x31534e54u)return NPU_ERROR;
    // 硬件/可见性边界：uint64_t begin=ticks64();graph_executor_batch_cap=R32(CONV_SERVICE_MMIO+0xbcu);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint64_t begin=ticks64();graph_executor_batch_cap=R32(CONV_SERVICE_MMIO+0xbcu);
    // 硬件/可见性边界：graph_executor_capacity=R32(GRAPH_EXECUTOR_MMIO+0x68u);graph_executor_words=0u;graph_executor_crc=UINT32_MAX;graph_executor_compile_error=0u;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    graph_executor_capacity=R32(GRAPH_EXECUTOR_MMIO+0x68u);graph_executor_words=0u;graph_executor_crc=UINT32_MAX;graph_executor_compile_error=0u;
    // 硬件/可见性边界：R32(GRAPH_EXECUTOR_MMIO+8u)=1u;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(GRAPH_EXECUTOR_MMIO+8u)=1u;
    graph_executor_check(CONV_SERVICE_MMIO+8u,CONV_SERVICE_ID,UINT32_MAX);
    graph_executor_check(S3_MMIO+0x40u,S3_ID,UINT32_MAX);graph_executor_check(CONCAT_MMIO+0x40u,0x31534e54u,UINT32_MAX);
    for(uint32_t i=0;i<count;i++) {
        const uint32_t *d=graph_words[i];uint32_t result,fused=0u;
        if(d[0]==10u)result=graph_executor_conv(i,d);
        else if(d[0]==11u)result=graph_executor_requant(i,count,d,&fused);
        else result=graph_executor_tensor(i,d);
        if(result!=OK)return result;
        if(graph_executor_compile_error)return graph_executor_compile_error;
        i+=fused;
    }
    // 硬件/可见性边界：graph_executor_emit(GX_END,count,0u,0u);fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    graph_executor_emit(GX_END,count,0u,0u);fence_all();
    if(graph_executor_compile_error||R32(GRAPH_EXECUTOR_MMIO+0x0cu)!=graph_executor_words||R32(GRAPH_EXECUTOR_MMIO+0x18u)!=(graph_executor_crc^UINT32_MAX))return GRAPH_BAD_DESCRIPTOR;
    // 硬件/可见性边界：R32(GRAPH_EXECUTOR_MMIO+0x10u)=graph_executor_words;R32(GRAPH_EXECUTOR_MMIO+0x14u)=graph_executor_crc^UINT32_MAX;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(GRAPH_EXECUTOR_MMIO+0x10u)=graph_executor_words;R32(GRAPH_EXECUTOR_MMIO+0x14u)=graph_executor_crc^UINT32_MAX;
    // 硬件/可见性边界：R32(GRAPH_EXECUTOR_MMIO+0x28u)=count;R32(GRAPH_EXECUTOR_MMIO+0x2cu)=HZ*5u;R32(GRAPH_EXECUTOR_MMIO+8u)=2u;fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(GRAPH_EXECUTOR_MMIO+0x28u)=count;R32(GRAPH_EXECUTOR_MMIO+0x2cu)=HZ*5u;R32(GRAPH_EXECUTOR_MMIO+8u)=2u;fence_all();
    if((R32(GRAPH_EXECUTOR_MMIO+4u)&13u)!=4u)return NPU_ERROR;
    graph_executor_model_epoch=conv_service_model_epoch;graph_executor_ready=1u;graph_executor_compile_ticks=ticks64()-begin;return OK;
}
// 服务函数 graph_hw_start。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static uint32_t graph_hw_start(void) {
    if(!graph_executor_ready||graph_executor_model_epoch!=conv_service_model_epoch||conv_service_timeout_latched||
       // 硬件/可见性边界：(R32(GRAPH_EXECUTOR_MMIO+4u)&13u)!=4u)return NPU_ERROR;。
       // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
       (R32(GRAPH_EXECUTOR_MMIO+4u)&13u)!=4u)return NPU_ERROR;
    // 硬件/可见性边界：R32(GRAPH_EXECUTOR_MMIO+0x20u)=conv_service_model_epoch;R32(GRAPH_EXECUTOR_MMIO+0x24u)=conv_service_frame_epoch;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(GRAPH_EXECUTOR_MMIO+0x20u)=conv_service_model_epoch;R32(GRAPH_EXECUTOR_MMIO+0x24u)=conv_service_frame_epoch;
    // 硬件/可见性边界：fence_all();R32(GRAPH_EXECUTOR_MMIO+8u)=4u;fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();R32(GRAPH_EXECUTOR_MMIO+8u)=4u;fence_all();
    graph_executor_starts++;rv32_layer_completed=0u;return OK;
}
// 服务函数 graph_hw_poll。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static uint32_t graph_hw_poll(void) {
    // 硬件/可见性边界：uint32_t start=ticks(),state=R32(GRAPH_EXECUTOR_MMIO+4u);graph_executor_polls++;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t start=ticks(),state=R32(GRAPH_EXECUTOR_MMIO+4u);graph_executor_polls++;
    graph_executor_cpu_poll_ticks+=(uint32_t)(ticks()-start);
    if(state&8u){conv_service_timeout_latched=1u;return NPU_ERROR;}
    if(state&2u)return OK;
    if(state&1u)return GRAPH_EXECUTOR_PENDING;
    conv_service_timeout_latched=1u;return NPU_ERROR;
}
// 服务函数 graph_hw_finish。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static uint32_t graph_hw_finish(void) {
    uint64_t v[32];
    if((R32(GRAPH_EXECUTOR_MMIO+4u)&11u)!=2u||R32(GRAPH_EXECUTOR_MMIO+0x34u)!=GRAPH_MAX_OPS){conv_service_timeout_latched=1u;return NPU_ERROR;}
    for(uint32_t i=0;i<32u;i++) {
        // 硬件/可见性边界：R32(GRAPH_EXECUTOR_MMIO+0x5cu)=i;。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        R32(GRAPH_EXECUTOR_MMIO+0x5cu)=i;
        // 硬件/可见性边界：uint32_t lo=R32(GRAPH_EXECUTOR_MMIO+0x60u),hi=R32(GRAPH_EXECUTOR_MMIO+0x64u);v[i]=(uint64_t)lo|((uint64_t)hi<<32);。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        uint32_t lo=R32(GRAPH_EXECUTOR_MMIO+0x60u),hi=R32(GRAPH_EXECUTOR_MMIO+0x64u);v[i]=(uint64_t)lo|((uint64_t)hi<<32);
    }
    // 硬件/可见性边界：R32(GRAPH_EXECUTOR_MMIO+0x54u)=0u;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(GRAPH_EXECUTOR_MMIO+0x54u)=0u;
    for(uint32_t i=0;i<GRAPH_MAX_OPS;i++)for(uint32_t j=0;j<4u;j++)rv32_layer_profile[i][j]=R32(GRAPH_EXECUTOR_MMIO+0x58u);
    rv32_layer_completed=GRAPH_MAX_OPS;
    // 硬件/可见性边界：profile_counters[P_GRAPH_TICKS]+=R32(GRAPH_EXECUTOR_MMIO+0x40u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    profile_counters[P_GRAPH_TICKS]+=R32(GRAPH_EXECUTOR_MMIO+0x40u);
    static const uint8_t profile_map[][2]={
        {23,P_CONV_TICKS},{24,P_HW_REQUANT_TICKS},{25,P_CONCAT_TICKS},{26,P_UPSAMPLE_TICKS},
        {27,P_ADD_TICKS},{28,P_POOL_TICKS},{0,P_NPU_COMPLETION_CYCLES},{1,P_NPU_COMMAND_TICKS},
        {9,P_WINDOW_GATHER_TICKS},{3,P_WINDOW_READ_BYTES},{4,P_WINDOW_WRITE_BYTES},
        {5,P_WINDOW_ACTIVE_UI_CYCLES},{6,P_WINDOW_STALL_UI_CYCLES},{10,P_S3_READ_BYTES},
        {11,P_S3_WRITE_BYTES},{12,P_S3_STALL_UI_CYCLES},{13,P_S3_ACTIVE_UI_CYCLES}};
    for(uint32_t i=0;i<sizeof(profile_map)/sizeof(profile_map[0]);i++)
        profile_counters[profile_map[i][1]]+=v[profile_map[i][0]];
    static uint64_t *const totals[]={&window_wait_total,&window_read_total,&window_write_total,
        &window_active_total,&window_stall_total,&window_hit_total,&window_miss_total,
        &s3_stall_cycles_total,&s3_active_cycles_total,
        &concat_read_total,&concat_write_total,&concat_active_total,&concat_stall_total};
    static const uint8_t total_map[]={9,3,4,5,6,7,8,12,13,14,15,16,17};
    for(uint32_t i=0;i<sizeof(total_map);i++)*totals[i]+=v[total_map[i]];
    static uint32_t *const jobs[]={&window_jobs,&window_hw_layers,&window_direct_layers,
        &s3_jobs,&s3_lut_jobs,&concat_jobs,&shared_tensor_jobs,&s3_read_total,&s3_write_total};
    static const uint8_t job_map[]={2,30,29,19,20,21,22,10,11};
    for(uint32_t i=0;i<sizeof(job_map);i++)*jobs[i]+=(uint32_t)v[job_map[i]];
    profile_batches++;profile_ops+=GRAPH_MAX_OPS;graph_executor_finishes++;
#ifdef BOARD_SIM_GRAPH_METRICS
    sim_npu_cycles+=v[0];sim_npu_commands+=v[31];
#endif
    return OK;
}
#endif
