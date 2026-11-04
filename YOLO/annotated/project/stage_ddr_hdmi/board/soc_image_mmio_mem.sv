// IMG1 image accelerator registers, CPU window 0x60001700.
// Addresses are absolute CPU DDR addresses; engines receive DDR byte offsets.
// 架构导读：soc_image_mmio_mem。
// 图像加速寄存器接口，保存源目标地址、尺寸及任务状态。
module soc_image_mmio_mem #(
    // 静态配置：parameter logic [31:0] DDR_BASE=32'h80000000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] DDR_BASE=32'h80000000,
    // 静态配置：parameter logic [31:0] DDR_END=32'h88000000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] DDR_END=32'h88000000
)(
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
    // 接口声明：output logic start,output logic mode。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic start,output logic mode,
    // 接口声明：output logic [29:0] src_base,dst_base。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [29:0] src_base,dst_base,
    // 接口声明：output logic lut_we,output logic [7:0] lut_idx,lut_dat。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic lut_we,output logic [7:0] lut_idx,lut_dat,
    // 接口声明：input logic engine_busy,engine_done,engine_error。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    input logic engine_busy,engine_done,engine_error,
    // 接口声明：input logic [31:0] active_cycles,read_beats,write_beats。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [31:0] active_cycles,read_beats,write_beats
);
    logic [31:0] source_q,dest_q;
    logic done_hold,error_hold,rejected_hold;
    logic [7:0] lut_index;
    logic [255:0] lut_written;
    wire [31:0] out_bytes=mode?32'd462400:32'd307200;
    wire valid_ranges=source_q>=DDR_BASE && source_q<=DDR_END-32'd1843200 &&
        dest_q>=DDR_BASE && dest_q<=DDR_END-out_bytes &&
        source_q[3:0]==0 && dest_q[3:0]==0 &&
        (({1'b0,dest_q}+{1'b0,out_bytes}<={1'b0,source_q}) ||
         ({1'b0,source_q}+33'd1843200<={1'b0,dest_q}));
    wire hit=req_addr[15:8]==8'h17 && req_addr[1:0]==0;
    assign req_ready=!rst&&!rsp_valid;
    assign src_base=30'(source_q-DDR_BASE);
    assign dst_base=30'(dest_q-DDR_BASE);
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        start<=0;lut_we<=0;
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst) begin
            source_q<=0;dest_q<=0;mode<=0;
            done_hold<=0;error_hold<=0;rejected_hold<=0;
            lut_written<=0;lut_index<=0;lut_idx<=0;lut_dat<=0;
            rsp_valid<=0;rsp_error<=0;rsp_rdata<=0;
        end else begin
            // 条件分支：检查 engine_done。
            if(engine_done) begin done_hold<=1;error_hold<=engine_error;end
            if(engine_error) error_hold<=1;
            // 握手/背压判断：rsp_valid&&rsp_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if(rsp_valid&&rsp_ready)rsp_valid<=0;
            // 握手/背压判断：req_valid&&req_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if(req_valid&&req_ready)begin
                rsp_valid<=1;rsp_error<=0;rsp_rdata<=0;
                if(!hit || (req_write&&req_wstrb!=4'hf))begin
                    rsp_error<=1;rejected_hold<=1;
                end else if(req_write)begin
                    if(engine_busy)begin rsp_error<=1;rejected_hold<=1;end
                    else case(req_addr[7:0])
                        8'h00:if(req_wdata!=1 || !ddr_ready || axi_poisoned ||
                            !valid_ranges || (!mode&&!(&lut_written)))begin
                            rsp_error<=1;rejected_hold<=1;
                        end else begin
                            start<=1;done_hold<=0;error_hold<=0;rejected_hold<=0;
                        end
                        8'h04:source_q<=req_wdata;
                        8'h08:dest_q<=req_wdata;
                        8'h0c:if(req_wdata>1)begin rsp_error<=1;rejected_hold<=1;end
                            else mode<=req_wdata[0];
                        8'h24:if(req_wdata==1)begin
                            done_hold<=0;error_hold<=0;rejected_hold<=0;
                        end else begin rsp_error<=1;rejected_hold<=1;end
                        8'h28:if(req_wdata>255)begin rsp_error<=1;rejected_hold<=1;end
                            else lut_index<=req_wdata[7:0];
                        8'h2c:if(req_wdata>255)begin rsp_error<=1;rejected_hold<=1;end
                            else begin
                                lut_we<=1;lut_idx<=lut_index;lut_dat<=req_wdata[7:0];
                                lut_written[lut_index]<=1;lut_index<=lut_index+1'b1;
                            end
                        default:begin rsp_error<=1;rejected_hold<=1;end
                    endcase
                end else case(req_addr[7:0])
                    8'h00:rsp_rdata<=0;
                    8'h04:rsp_rdata<=source_q;
                    8'h08:rsp_rdata<=dest_q;
                    8'h0c:rsp_rdata<={31'd0,mode};
                    8'h10:rsp_rdata<={26'd0,axi_poisoned,ddr_ready,rejected_hold,
                        (error_hold||engine_error),done_hold,engine_busy};
                    8'h14:rsp_rdata<=active_cycles;
                    8'h18:rsp_rdata<=read_beats;
                    8'h1c:rsp_rdata<=write_beats;
                    8'h20:rsp_rdata<=32'h494d4731;
                    8'h24:rsp_rdata<=0;
                    8'h28:rsp_rdata<={24'd0,lut_index};
                    8'h2c:rsp_rdata<=0;
                    default:begin rsp_error<=1;rejected_hold<=1;end
                endcase
            end
        end
    end
endmodule
