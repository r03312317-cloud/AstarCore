// 架构导读：soc_window_mmio_mem。
// Window 参数寄存器和任务状态接口，供图执行器/卷积服务访问。
`timescale 1ns/1ps
// Window Gather control at board MMIO 0x60001300..0x6000134c.
// pg_mmio_cdc is upstream, so all registers and engine live in DDR UI domain.
module soc_window_mmio_mem(
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
    // 接口声明：output logic engine_start,input logic engine_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic engine_start,input logic engine_ready,
    // 接口声明：input logic engine_done,input logic [7:0] engine_error。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    input logic engine_done,input logic [7:0] engine_error,
    // 接口声明：input logic engine_partial。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic engine_partial,
    // 接口声明：input logic [31:0] engine_read_bytes,engine_write_bytes。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [31:0] engine_read_bytes,engine_write_bytes,
    // 接口声明：input logic [31:0] engine_cache_hits,engine_cache_misses。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [31:0] engine_cache_hits,engine_cache_misses,
    // 接口声明：input logic [31:0] engine_active_cycles,engine_stall_cycles。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [31:0] engine_active_cycles,engine_stall_cycles,
    // 接口声明：output logic [31:0] input_base,scratch_base,first_row。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    output logic [31:0] input_base,scratch_base,first_row,
    // 接口声明：output logic [15:0] input_h,input_w,input_c,output_h,output_w。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [15:0] input_h,input_w,input_c,output_h,output_w,
    // 接口声明：output logic [15:0] first_oy,first_ox,row_count。
    // 记录数量或剩余进度，位宽限定可表达范围。
    output logic [15:0] first_oy,first_ox,row_count,
    // 接口声明：output logic [7:0] kernel_h,kernel_w,stride_h,stride_w。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [7:0] kernel_h,kernel_w,stride_h,stride_w,
    // 接口声明：output logic [7:0] dilation_h,dilation_w。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [7:0] dilation_h,dilation_w,
    output logic [7:0] pad_top,pad_left,pad_bottom,pad_right,
    output logic flush_cache
);
    // 静态配置：localparam logic [31:0] ID=32'h314e_4957;。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [31:0] ID=32'h314e_4957; // "WIN1"
    logic busy_q,done_q,rejected_q,partial_q;
    logic [7:0] error_q;
    logic [31:0] flags_q;
    wire hit=req_addr>=16'h0300 && req_addr<=16'h034c &&
             req_addr[1:0]==0;
    assign req_ready=!rst && !rsp_valid;
    assign flush_cache=flags_q[0];
    // 过程边界：always_ff @(posedge clk)begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk)begin
        engine_start<=0;
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst)begin
            rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;
            busy_q<=0;done_q<=0;rejected_q<=0;partial_q<=0;error_q<=0;
            input_base<=0;scratch_base<=0;first_row<=0;
            input_h<=0;input_w<=0;input_c<=0;output_h<=0;output_w<=0;
            first_oy<=0;first_ox<=0;row_count<=0;
            kernel_h<=0;kernel_w<=0;stride_h<=0;stride_w<=0;
            dilation_h<=0;dilation_w<=0;
            pad_top<=0;pad_left<=0;pad_bottom<=0;pad_right<=0;
            flags_q<=0;
        end else begin
            if(engine_done)begin
                busy_q<=0;done_q<=1;error_q<=engine_error;
                partial_q<=engine_partial;
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
                    if(busy_q)begin rsp_error<=1;rejected_q<=1;end
                    else case(req_addr)
                        16'h0300:if(req_wdata!=1 || !engine_ready ||
                                     !ddr_ready || axi_poisoned)begin
                            rsp_error<=1;rejected_q<=1;
                        end else begin
                            engine_start<=1;busy_q<=1;done_q<=0;
                            rejected_q<=0;partial_q<=0;error_q<=0;
                        end
                        16'h0304:input_base<=req_wdata;
                        16'h0308:scratch_base<=req_wdata;
                        16'h030c:first_row<=req_wdata;
                        16'h0310:{input_w,input_h}<=req_wdata;
                        16'h0314:{output_h,input_c}<=req_wdata;
                        16'h0318:{first_oy,output_w}<=req_wdata;
                        16'h031c:{row_count,first_ox}<=req_wdata;
                        16'h0320:{stride_w,stride_h,kernel_w,kernel_h}<=req_wdata;
                        16'h0324:{pad_left,pad_top,dilation_w,dilation_h}<=req_wdata;
                        16'h0328:if(req_wdata[31:16]!=0)begin
                            rsp_error<=1;rejected_q<=1;
                        end else {pad_right,pad_bottom}<=req_wdata[15:0];
                        16'h032c:if(req_wdata[31:1]!=0)begin
                            rsp_error<=1;rejected_q<=1;
                        end else flags_q<=req_wdata;
                        16'h0330:if(req_wdata==1)begin
                            done_q<=0;rejected_q<=0;partial_q<=0;error_q<=0;
                        end else begin rsp_error<=1;rejected_q<=1;end
                        default:begin rsp_error<=1;rejected_q<=1;end
                    endcase
                end else case(req_addr)
                    16'h0300:rsp_rdata<=0;
                    16'h0304:rsp_rdata<=input_base;
                    16'h0308:rsp_rdata<=scratch_base;
                    16'h030c:rsp_rdata<=first_row;
                    16'h0310:rsp_rdata<={input_w,input_h};
                    16'h0314:rsp_rdata<={output_h,input_c};
                    16'h0318:rsp_rdata<={first_oy,output_w};
                    16'h031c:rsp_rdata<={row_count,first_ox};
                    16'h0320:rsp_rdata<={stride_w,stride_h,kernel_w,kernel_h};
                    16'h0324:rsp_rdata<={pad_left,pad_top,dilation_w,dilation_h};
                    16'h0328:rsp_rdata<={16'd0,pad_right,pad_bottom};
                    16'h032c:rsp_rdata<=flags_q;
                    16'h0330:rsp_rdata<={14'd0,engine_ready,axi_poisoned,ddr_ready,
                        rejected_q,partial_q,error_q,3'd0,done_q,busy_q};
                    16'h0334:rsp_rdata<=engine_read_bytes;
                    16'h0338:rsp_rdata<=engine_write_bytes;
                    16'h033c:rsp_rdata<=engine_cache_hits;
                    16'h0340:rsp_rdata<=engine_cache_misses;
                    16'h0344:rsp_rdata<=engine_active_cycles;
                    16'h0348:rsp_rdata<=engine_stall_cycles;
                    16'h034c:rsp_rdata<=ID;
                    default:begin rsp_error<=1;rejected_q<=1;end
                endcase
            end
        end
    end
endmodule
