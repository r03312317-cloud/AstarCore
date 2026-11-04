// 架构导读：soc_concat_mmio_mem。
// Concat 的任务参数、状态和计数寄存器。
`timescale 1ns/1ps
// CPU reaches these DDR UI registers through the existing pg_mmio_cdc.
// Extends the existing Concat register bank through0x60001440. Its original
// addresses/ID remain. One engine and one native port serve all four modes.
module soc_concat_mmio_mem(
    // 接口声明：input logic clk,rst,ddr_ready,axi_poisoned。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    input logic clk,rst,ddr_ready,axi_poisoned,
    // 接口声明：input logic req_valid,output logic req_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic req_valid,output logic req_ready,
    // 接口声明：input logic [15:0] req_addr,input logic req_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [15:0] req_addr,input logic req_write,
    // 接口声明：input logic [31:0] req_wdata,input logic [3:0] req_wstrb。
    // 按字节选择本次写入生效的 lane。
    input logic [31:0] req_wdata,input logic [3:0] req_wstrb,
    // 接口声明：output logic rsp_valid,input logic rsp_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic rsp_valid,input logic rsp_ready,
    // 接口声明：output logic [31:0] rsp_rdata,output logic rsp_error。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic [31:0] rsp_rdata,output logic rsp_error,
    // 接口声明：output logic engine_start,engine_cancel,input logic engine_ready,engine_done。
    // 表达本地完成/结束条件，系统退休还需满足上层接口契约。
    output logic engine_start,engine_cancel,input logic engine_ready,engine_done,
    // 接口声明：input logic [7:0] engine_error,input logic engine_partial。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [7:0] engine_error,input logic engine_partial,
    // 接口声明：input logic [31:0] engine_read_bytes,engine_write_bytes。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [31:0] engine_read_bytes,engine_write_bytes,
    // 接口声明：input logic [31:0] engine_active_cycles,engine_stall_cycles。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [31:0] engine_active_cycles,engine_stall_cycles,
    // 接口声明：output logic [31:0] input_base,aux_base,output_base,pixels。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] input_base,aux_base,output_base,pixels,
    // 接口声明：output logic [15:0] input_channels,aux_channels。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [15:0] input_channels,aux_channels,
    output logic [1:0] operation,
    output logic [15:0] image_h,image_w,
    output logic irq_level
);
    // 静态配置：localparam logic [31:0] ID=32'h3154_4143;。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [31:0] ID=32'h3154_4143; // CAT1
    logic busy_q,done_q,partial_q,rejected_q,irq_enable_q;
    logic [7:0] error_q;
    wire hit=req_addr>=16'h0400 && req_addr<=16'h0440 && req_addr[1:0]==0;
    assign req_ready=!rst && !rsp_valid;
    assign irq_level=done_q && irq_enable_q;
    // 过程边界：always_ff @(posedge clk)begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk)begin
        engine_start<=0;
        engine_cancel<=0;
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst)begin
            rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;
            busy_q<=0;done_q<=0;partial_q<=0;rejected_q<=0;irq_enable_q<=0;error_q<=0;
            input_base<=0;aux_base<=0;output_base<=0;pixels<=0;
            input_channels<=0;aux_channels<=0;
            operation<=0;image_h<=0;image_w<=0;
        end else begin
            if(engine_done)begin
                busy_q<=0;done_q<=1;error_q<=engine_error;partial_q<=engine_partial;
            end
            // 握手/背压判断：rsp_valid && rsp_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if(rsp_valid && rsp_ready)rsp_valid<=0;
            // 握手/背压判断：req_valid && req_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if(req_valid && req_ready)begin
                rsp_valid<=1;rsp_rdata<=0;rsp_error<=0;
                if(!hit || (req_write && req_wstrb!=4'hf))begin
                    rsp_error<=1;rejected_q<=1;
                end else if(req_write)begin
                    if(busy_q && req_addr==16'h0400 && req_wdata==2)begin
                        // Cancel requests drain an already-held request and
                        // real response inside the engine. Busy is retained.
                        engine_cancel<=1;
                    end else if(busy_q)begin rsp_error<=1;rejected_q<=1;end
                    else case(req_addr)
                        16'h0400:if(req_wdata!=1 || !engine_ready ||
                                     !ddr_ready || axi_poisoned)begin
                            rsp_error<=1;rejected_q<=1;
                        end else begin
                            engine_start<=1;busy_q<=1;done_q<=0;
                            error_q<=0;partial_q<=0;rejected_q<=0;
                        end
                        16'h0404:input_base<=req_wdata;
                        16'h0408:aux_base<=req_wdata;
                        16'h040c:output_base<=req_wdata;
                        16'h0410:pixels<=req_wdata;
                        16'h0414:{aux_channels,input_channels}<=req_wdata;
                        16'h0418:if(req_wdata<=1)irq_enable_q<=req_wdata[0];
                            else begin rsp_error<=1;rejected_q<=1;end
                        16'h0430:if(req_wdata==1)begin
                            done_q<=0;partial_q<=0;error_q<=0;rejected_q<=0;
                        end else begin rsp_error<=1;rejected_q<=1;end
                        16'h0438:if(req_wdata<=3)operation<=req_wdata[1:0];
                            else begin rsp_error<=1;rejected_q<=1;end
                        16'h043c:{image_h,image_w}<=req_wdata;
                        default:begin rsp_error<=1;rejected_q<=1;end
                    endcase
                end else case(req_addr)
                    16'h0400:rsp_rdata<=0;
                    16'h0404:rsp_rdata<=input_base;
                    16'h0408:rsp_rdata<=aux_base;
                    16'h040c:rsp_rdata<=output_base;
                    16'h0410:rsp_rdata<=pixels;
                    16'h0414:rsp_rdata<={aux_channels,input_channels};
                    16'h0418:rsp_rdata<={31'd0,irq_enable_q};
                    16'h041c:rsp_rdata<={14'd0,engine_ready,axi_poisoned,ddr_ready,
                        rejected_q,partial_q,error_q,3'd0,done_q,busy_q};
                    16'h0420:rsp_rdata<=engine_read_bytes;
                    16'h0424:rsp_rdata<=engine_write_bytes;
                    16'h0428:rsp_rdata<=engine_active_cycles;
                    16'h042c:rsp_rdata<=engine_stall_cycles;
                    16'h0430:rsp_rdata<=0;
                    16'h0434:rsp_rdata<=ID;
                    16'h0438:rsp_rdata<={30'd0,operation};
                    16'h043c:rsp_rdata<={image_h,image_w};
                    16'h0440:rsp_rdata<=32'h31534e54; // TNS1
                    default:begin rsp_error<=1;rejected_q<=1;end
                endcase
            end
        end
    end
endmodule
