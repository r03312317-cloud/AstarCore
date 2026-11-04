// 架构导读：soc_v2_axi_writer。
// 可综合数据/控制组件；接口含义和更新条件以下面的局部注释及原始表达式为准。
`timescale 1ns/1ps
// Functional RGB INT8 HWC writer. Single-beat AXI writes keep every request
// inside a 4 KiB page. A frame is committed only after producer completion
// and all 19,200 write responses have succeeded.
module soc_v2_axi_writer (
    // 接口声明：input logic clk,rst,start。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic clk,rst,start,
    // 接口声明：input logic [31:0] destination。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [31:0] destination,
    // 接口声明：input logic producer_done,producer_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input logic producer_done,producer_valid,
    // 接口声明：input logic pixel_valid,pixel_last。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic pixel_valid,pixel_last,
    // 接口声明：output logic pixel_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic pixel_ready,
    // 接口声明：input logic [23:0] pixel_rgb_i8。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [23:0] pixel_rgb_i8,
    // 接口声明：output logic busy,done_pulse,frame_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic busy,done_pulse,frame_valid,
    // 接口声明：output logic [7:0] error_sticky。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic [7:0] error_sticky,
    // 接口声明：output logic [31:0] pixels_accepted,bytes_written。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] pixels_accepted,bytes_written,
    // 接口声明：output logic [3:0] m_awid。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [3:0] m_awid,
    // 接口声明：output logic [31:0] m_awaddr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [31:0] m_awaddr,
    // 接口声明：output logic [7:0] m_awlen。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [7:0] m_awlen,
    // 接口声明：output logic [2:0] m_awsize。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [2:0] m_awsize,
    // 接口声明：output logic [1:0] m_awburst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    output logic [1:0] m_awburst,
    // 接口声明：output logic m_awvalid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic m_awvalid,
    // 接口声明：input logic m_awready。
    input logic m_awready,
    output logic [127:0] m_wdata,
    output logic [15:0] m_wstrb,
    output logic m_wlast,m_wvalid,
    input logic m_wready,
    input logic [3:0] m_bid,
    input logic [1:0] m_bresp,
    input logic m_bvalid,
    output logic m_bready
);
    // 静态配置：localparam logic [31:0] BASE=32'h8000_0000,END_ADDR=32'h8400_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [31:0] BASE=32'h8000_0000,END_ADDR=32'h8400_0000;
    // 静态配置：localparam int PIXELS=320*320,BYTES=PIXELS*3。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam int PIXELS=320*320,BYTES=PIXELS*3;
    typedef enum logic [2:0] {IDLE,FILL,ADDR,DATA,RESP} state_t;
    state_t state;
    logic [127:0] stage_data;
    logic [15:0] carry_data;
    logic [1:0] carry_count;
    logic [4:0] fill_bytes;
    logic [31:0] write_addr;
    logic producer_done_seen,producer_good_seen;
    logic [31:0] byte_position;
    assign busy=state!=IDLE;
    assign pixel_ready=state==FILL && pixels_accepted<PIXELS &&
                       !producer_done_seen;
    assign m_awid=4'he;
    assign m_awaddr=write_addr;
    assign m_awlen=0;
    assign m_awsize=3'd4;
    assign m_awburst=2'b01;
    assign m_awvalid=state==ADDR;
    assign m_wdata=stage_data;
    assign m_wstrb=16'hffff;
    assign m_wlast=1'b1;
    assign m_wvalid=state==DATA;
    assign m_bready=state==RESP;
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        done_pulse<=0;
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst) begin
            state<=IDLE;stage_data<=0;carry_data<=0;carry_count<=0;
            fill_bytes<=0;write_addr<=0;pixels_accepted<=0;bytes_written<=0;
            producer_done_seen<=0;producer_good_seen<=0;
            frame_valid<=0;error_sticky<=0;
        end else begin
            if(start && state!=IDLE)error_sticky[4]<=1;
            if(state!=IDLE && producer_done)begin
                producer_done_seen<=1;
                producer_good_seen<=producer_valid;
                if(!producer_valid)error_sticky[2]<=1;
            end
            // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case(state)
                // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                IDLE: if(start) begin
                    stage_data<=0;carry_data<=0;carry_count<=0;
                    fill_bytes<=0;write_addr<=destination;
                    pixels_accepted<=0;bytes_written<=0;
                    producer_done_seen<=0;producer_good_seen<=0;
                    frame_valid<=0;error_sticky<=0;
                    if(destination[3:0]!=0 || destination<BASE ||
                       destination>END_ADDR-BYTES)begin
                        error_sticky[0]<=1;done_pulse<=1;
                    end else state<=FILL;
                end
                // 状态/选择分支 FILL：本分支规定该编码下的寄存器更新和下一步动作。
                FILL:begin
                    // 握手/背压判断：pixel_valid && pixel_ready。
                    // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
                    if(pixel_valid && pixel_ready)begin
                        for(int b=0;b<3;b++)begin
                            if(fill_bytes+5'(b)<16)
                                stage_data[8*(fill_bytes+5'(b))+:8]<=pixel_rgb_i8[8*b+:8];
                            else carry_data[8*(fill_bytes+5'(b)-5'd16)+:8]<=pixel_rgb_i8[8*b+:8];
                        end
                        pixels_accepted<=pixels_accepted+1;
                        if(pixel_last!=(pixels_accepted==PIXELS-1))
                            error_sticky[1]<=1;
                        if(fill_bytes+5'd3>=16)begin
                            carry_count<=2'(fill_bytes+5'd3-5'd16);
                            state<=ADDR;
                        end else fill_bytes<=fill_bytes+5'd3;
                    end else if(producer_done_seen)begin
                        if(pixels_accepted!=PIXELS || fill_bytes!=0 ||
                           bytes_written!=BYTES || !producer_good_seen ||
                           error_sticky!=0) begin
                            error_sticky[3]<=pixels_accepted!=PIXELS ||
                                             fill_bytes!=0 || bytes_written!=BYTES;
                            frame_valid<=0;
                        end else frame_valid<=1;
                        done_pulse<=1;state<=IDLE;
                    end
                end
                // 状态/选择分支 ADDR：本分支规定该编码下的寄存器更新和下一步动作。
                ADDR:if(m_awready)state<=DATA;
                // 状态/选择分支 DATA：本分支规定该编码下的寄存器更新和下一步动作。
                DATA:if(m_wready)state<=RESP;
                // 状态/选择分支 RESP：本分支规定该编码下的寄存器更新和下一步动作。
                RESP:if(m_bvalid)begin
                    if(m_bid!=4'he || m_bresp!=2'b00)error_sticky[5]<=1;
                    bytes_written<=bytes_written+16;
                    write_addr<=write_addr+16;
                    stage_data<=128'(carry_data);
                    fill_bytes<=5'(carry_count);
                    carry_data<=0;carry_count<=0;
                    state<=FILL;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
