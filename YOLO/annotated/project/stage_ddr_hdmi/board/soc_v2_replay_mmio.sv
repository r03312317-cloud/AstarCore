// 架构导读：soc_v2_replay_mmio。
// 可综合数据/控制组件；接口含义和更新条件以下面的局部注释及原始表达式为准。
`timescale 1ns/1ps
// CPU control at 0x60001200 in the DDR UI domain, behind pg_mmio_cdc.
// Source 0x81000000..0x82ffffff is within the existing validated 64 MiB
// DDR aperture. Destination stays below 0x81000000 to prevent aliasing.
module soc_v2_replay_mmio (
    // 接口声明：input logic clk,rst,ddr_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic clk,rst,ddr_ready,
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
    // 接口声明：output logic start。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic start,
    // 接口声明：output logic [31:0] source_addr,destination_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [31:0] source_addr,destination_addr,
    // 接口声明：output logic lut_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic lut_write,
    // 接口声明：output logic [7:0] lut_addr,lut_data。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    output logic [7:0] lut_addr,lut_data,
    // 接口声明：input logic lut_ready,lut_complete。
    // 表达本地完成/结束条件，系统退休还需满足上层接口契约。
    input logic lut_ready,lut_complete,
    // 接口声明：input logic reader_ready,reader_done,reader_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input logic reader_ready,reader_done,reader_valid,
    // 接口声明：input logic [7:0] reader_errors。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    input logic [7:0] reader_errors,
    // 接口声明：input logic stream_ready,stream_done,stream_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input logic stream_ready,stream_done,stream_valid,
    // 接口声明：input logic [7:0] stream_errors。
    input logic [7:0] stream_errors,
    input logic writer_busy,writer_done,writer_valid,
    input logic [7:0] writer_errors,
    input logic [31:0] source_pixels,active_pixels,output_pixels,
    input logic [31:0] bytes_written
);
    // 静态配置：localparam logic [31:0] SOURCE_BYTES=2592*1944*2。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [31:0] SOURCE_BYTES=2592*1944*2;
    // 静态配置：localparam logic [31:0] DEST_BYTES=320*320*3。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [31:0] DEST_BYTES=320*320*3;
    logic job_busy,done_hold,valid_hold,rejected_hold;
    logic [7:0] lut_index;
    logic [31:0] status_word;
    logic request_fire;
    assign req_ready=!rst && !rsp_valid;
    assign request_fire=req_valid && req_ready;
    assign lut_addr=lut_index;
    assign lut_data=req_wdata[7:0];
    assign lut_write=request_fire && req_write && req_addr==16'h0230 &&
                     req_wstrb==4'hf && req_wdata[31:8]==0 &&
                     !job_busy && lut_ready;
    assign status_word={25'd0,ddr_ready,
                        (|reader_errors)||(|stream_errors)||(|writer_errors)||rejected_hold,
                        lut_complete,valid_hold,done_hold,job_busy,
                        reader_ready&&stream_ready&&!writer_busy&&ddr_ready};
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        start<=0;
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst)begin
            rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;
            source_addr<=32'h8100_0000;destination_addr<=32'h8010_0000;
            lut_index<=0;job_busy<=0;done_hold<=0;valid_hold<=0;
            rejected_hold<=0;
        end else begin
            if(writer_done)begin
                job_busy<=0;done_hold<=1;valid_hold<=writer_valid;
            end
            // 握手/背压判断：rsp_valid && rsp_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if(rsp_valid && rsp_ready)rsp_valid<=0;
            if(request_fire)begin
                rsp_valid<=1;rsp_rdata<=0;rsp_error<=0;
                if(req_addr<16'h0200 || req_addr>16'h0234 || req_addr[1:0]!=0 ||
                   (req_write && req_wstrb!=4'hf))begin
                    rsp_error<=1;rejected_hold<=1;
                end else if(req_write)begin
                    // 按 req_addr 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                    case(req_addr)
                        16'h0200: if(req_wdata!=1 || job_busy || !ddr_ready ||
                                       !reader_ready || !stream_ready || writer_busy ||
                                       !lut_complete || source_addr[7:0]!=0 ||
                                       source_addr<32'h8100_0000 ||
                                       source_addr>32'h8300_0000-SOURCE_BYTES ||
                                       destination_addr[3:0]!=0 ||
                                       destination_addr<32'h8000_0000 ||
                                       destination_addr>32'h8100_0000-DEST_BYTES)begin
                            rsp_error<=1;rejected_hold<=1;
                        end else begin
                            start<=1;job_busy<=1;done_hold<=0;
                            valid_hold<=0;rejected_hold<=0;
                        end
                        16'h0204:if(!job_busy)source_addr<=req_wdata;
                                  else begin rsp_error<=1;rejected_hold<=1;end
                        16'h0208:if(!job_busy)destination_addr<=req_wdata;
                                  else begin rsp_error<=1;rejected_hold<=1;end
                        16'h022c:if(!job_busy && lut_ready && req_wdata[31:8]==0)
                                      lut_index<=req_wdata[7:0];
                                  else begin rsp_error<=1;rejected_hold<=1;end
                        16'h0230:if(lut_write)lut_index<=lut_index+1;
                                  else begin rsp_error<=1;rejected_hold<=1;end
                        default:begin rsp_error<=1;rejected_hold<=1;end
                    endcase
                end else case(req_addr)
                    16'h0200:rsp_rdata<=0;
                    16'h0204:rsp_rdata<=source_addr;
                    16'h0208:rsp_rdata<=destination_addr;
                    16'h020c:rsp_rdata<=status_word;
                    16'h0210:rsp_rdata<=source_pixels;
                    16'h0214:rsp_rdata<=active_pixels;
                    16'h0218:rsp_rdata<=output_pixels;
                    16'h021c:rsp_rdata<=bytes_written;
                    16'h0220:rsp_rdata<={23'd0,reader_valid,reader_errors};
                    16'h0224:rsp_rdata<={23'd0,stream_valid,stream_errors};
                    16'h0228:rsp_rdata<={23'd0,writer_valid,writer_errors};
                    16'h022c:rsp_rdata<={24'd0,lut_index};
                    16'h0230:rsp_rdata<=0;
                    16'h0234:rsp_rdata<=32'h3256_3253; // "S2V2"
                    default:begin rsp_error<=1;rejected_hold<=1;end
                endcase
            end
        end
    end
endmodule
