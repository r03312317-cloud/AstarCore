// One-frame RGB565 writer. Pixel input is already in the HMIC user clock
// domain, normally after soc_camera_async_fifo. A 256-byte staging bank
// decouples the DVP byte clock from one AXI INCR burst at a time. The caller
// owns the destination until done_pulse and must not arm another frame first.
// An invalid/short frame may leave partial data in DDR; frame_valid stays low.
// 架构导读：soc_camera_axi_writer。
// 把摄像头流写入 DDR，只有最后写响应退休后才具备完整帧完成证据。
module soc_camera_axi_writer #(
    // 静态配置：parameter logic [31:0] DDR_BASE = 32'h8000_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] DDR_BASE = 32'h8000_0000,
    // 静态配置：parameter logic [31:0] DDR_BYTES = 32'h0400_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] DDR_BYTES = 32'h0400_0000,
    // 静态配置：parameter int MAX_PIXELS = 1280*720。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int MAX_PIXELS = 1280*720
)(
    // 接口声明：input logic clk, rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input logic clk, rst,
    // 接口声明：input logic start。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic start,
    // 接口声明：input logic [31:0] frame_base, frame_pixels。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [31:0] frame_base, frame_pixels,
    // 接口声明：input logic sensor_done, sensor_bad。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic sensor_done, sensor_bad,
    // 接口声明：input logic pixel_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input logic pixel_valid,
    // 接口声明：output logic pixel_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic pixel_ready,
    // 接口声明：input logic [15:0] pixel_data。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input logic [15:0] pixel_data,
    // 接口声明：output logic busy, done_pulse, frame_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic busy, done_pulse, frame_valid,
    // 接口声明：output logic [7:0] error_sticky。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic [7:0] error_sticky,
    // 接口声明：output logic [31:0] pixels_written。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] pixels_written,
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
    output logic m_awvalid,
    input logic m_awready,
    output logic [127:0] m_wdata,
    output logic [15:0] m_wstrb,
    output logic m_wlast, m_wvalid,
    input logic m_wready,
    input logic [3:0] m_bid,
    input logic [1:0] m_bresp,
    input logic m_bvalid,
    output logic m_bready
);
    timeunit 1ns; timeprecision 1ps;
    typedef enum logic [2:0] {IDLE, FILL, ADDR, DATA, RESP} state_t;
    state_t state;
    logic [127:0] stage [0:15];
    logic [31:0] base_q, target_q, accepted_q, write_addr_q;
    logic [7:0] fill_pixels_q, chunk_pixels_q;
    logic [4:0] beats_q;
    logic [4:0] beat_index_q;
    logic [15:0] last_strb_q;
    logic [7:0] faults_q;
    logic [33:0] frame_end;
    logic valid_config;
    logic [7:0] filled_beats;
    logic [2:0] tail_pixels;

    assign frame_end={2'b0,frame_base}+{1'b0,frame_pixels,1'b0};
    assign valid_config=(frame_base[7:0]==0) && frame_pixels!=0 &&
        frame_pixels<=32'(MAX_PIXELS) && frame_base>=DDR_BASE &&
        frame_end<={2'b0,DDR_BASE}+{2'b0,DDR_BYTES};
    assign busy=(state!=IDLE);
    assign pixel_ready=(state==FILL) && accepted_q<target_q &&
        fill_pixels_q<8'd128;
    assign m_awid=4'hc;
    assign m_awaddr=write_addr_q;
    assign m_awlen=8'(beats_q-1'b1);
    assign m_awsize=3'd4;
    assign m_awburst=2'b01;
    assign m_awvalid=(state==ADDR);
    assign m_wdata=stage[beat_index_q[3:0]];
    assign m_wstrb=(beat_index_q==beats_q-1'b1) ? last_strb_q : 16'hffff;
    assign m_wlast=(beat_index_q==beats_q-1'b1);
    assign m_wvalid=(state==DATA);
    assign m_bready=(state==RESP);
    assign error_sticky=faults_q;
    assign filled_beats=(fill_pixels_q+8'd7)>>3;
    assign tail_pixels=fill_pixels_q[2:0];

    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        done_pulse<=0;
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst) begin
            state<=IDLE; base_q<=0; target_q<=0; accepted_q<=0;
            write_addr_q<=0; fill_pixels_q<=0; chunk_pixels_q<=0;
            beats_q<=0; beat_index_q<=0; last_strb_q<=0;
            faults_q<=0; pixels_written<=0; frame_valid<=0;
        end else begin
            // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case(state)
                // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                IDLE: if(start) begin
                    base_q<=frame_base; target_q<=frame_pixels;
                    accepted_q<=0; pixels_written<=0;
                    write_addr_q<=frame_base; fill_pixels_q<=0;
                    chunk_pixels_q<=0; beats_q<=0; beat_index_q<=0;
                    faults_q<=0; frame_valid<=0;
                    if(valid_config) state<=FILL;
                    else begin faults_q[2]<=1; done_pulse<=1; end
                end
                // 状态/选择分支 FILL：本分支规定该编码下的寄存器更新和下一步动作。
                FILL: begin
                    // 握手/背压判断：pixel_valid && pixel_ready。
                    // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
                    if(pixel_valid && pixel_ready) begin
                        stage[fill_pixels_q[6:3]][16*fill_pixels_q[2:0]+:16]<=pixel_data;
                        fill_pixels_q<=fill_pixels_q+1'b1;
                        accepted_q<=accepted_q+1'b1;
                    end else if(fill_pixels_q==8'd128 ||
                               (fill_pixels_q!=0 && (accepted_q==target_q ||
                                                     (sensor_done && !pixel_valid)))) begin
                        chunk_pixels_q<=fill_pixels_q;
                        beats_q<=5'(filled_beats);
                        last_strb_q<=tail_pixels==0 ? 16'hffff :
                            ((16'h0001 << (2*tail_pixels))-16'h0001);
                        beat_index_q<=0;
                        state<=ADDR;
                    end else if(sensor_done && (accepted_q==target_q || !pixel_valid)) begin
                        if(accepted_q!=target_q) faults_q[0]<=1;
                        if(pixel_valid) faults_q[3]<=1;
                        if(sensor_bad) faults_q[4]<=1;
                        frame_valid<=(accepted_q==target_q) && !pixel_valid &&
                                     !sensor_bad && faults_q==0;
                        done_pulse<=1;
                        state<=IDLE;
                    end
                end
                // 状态/选择分支 ADDR：本分支规定该编码下的寄存器更新和下一步动作。
                ADDR: if(m_awready) state<=DATA;
                // 状态/选择分支 DATA：本分支规定该编码下的寄存器更新和下一步动作。
                DATA: if(m_wready) begin
                    if(m_wlast) state<=RESP;
                    else beat_index_q<=beat_index_q+1'b1;
                end
                // 状态/选择分支 RESP：本分支规定该编码下的寄存器更新和下一步动作。
                RESP: if(m_bvalid) begin
                    if(m_bid!=4'hc || m_bresp!=2'b00) faults_q[1]<=1;
                    pixels_written<=pixels_written+32'(chunk_pixels_q);
                    write_addr_q<=write_addr_q+{23'b0,beats_q,4'b0};
                    fill_pixels_q<=0;
                    state<=FILL;
                end
                default: state<=IDLE;
            endcase
        end
    end
    initial begin
        if(MAX_PIXELS<1 || DDR_BYTES<256 || DDR_BASE[7:0]!=0)
            $fatal(1,"CAMERA_AXI_WRITER_PARAMETER");
    end
endmodule
