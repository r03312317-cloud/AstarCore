// Buffered image DMA adapter. Core addresses are byte offsets from DDR_BASE.
// Reads fetch an aligned 256-byte cache line before returning the requested
// beat; one core request is sufficient to make progress. All AXI R beats are
// absorbed without downstream backpressure. Writes are gathered into bursts
// of at most 16 beats, split at discontinuities and 4 KiB boundaries. The
// frame_finish pulse flushes the final partial burst. Completion waits for B.
// Error bits: 0 bad core address, 1 RRESP, 2 RID/RLAST, 3 BRESP, 4 BID.
// A protocol error poisons the port until common reset. Already advertised
// transactions drain; subsequent core accesses return zero/drop writes so
// the caller can finish its frame and report failure without publishing it.
// 架构导读：soc_image_axi_adapter。
// 将图像加速请求转换为共享 DDR 接口事务。
module soc_image_axi_adapter #(
    // 静态配置：parameter logic [31:0] DDR_BASE = 32'h8000_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] DDR_BASE = 32'h8000_0000,
    // 静态配置：parameter logic [30:0] DDR_BYTES = 31'h0800_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [30:0] DDR_BYTES = 31'h0800_0000,
    // 静态配置：parameter logic [3:0] AXI_ID = 4'he。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [3:0] AXI_ID = 4'he
)(
    // 接口声明：input logic clk, rst, frame_start, frame_finish。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic clk, rst, frame_start, frame_finish,
    // 接口声明：input logic rd_valid, output logic rd_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic rd_valid, output logic rd_ready,
    // 接口声明：input logic [29:0] rd_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input logic [29:0] rd_addr,
    // 接口声明：output logic rsp_valid, input logic rsp_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic rsp_valid, input logic rsp_ready,
    // 接口声明：output logic [127:0] rsp_data。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    output logic [127:0] rsp_data,
    // 接口声明：input logic wr_valid, output logic wr_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic wr_valid, output logic wr_ready,
    // 接口声明：input logic [29:0] wr_addr, input logic [127:0] wr_data。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input logic [29:0] wr_addr, input logic [127:0] wr_data,
    // 接口声明：output logic idle, drained。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic idle, drained,
    // 接口声明：output logic [7:0] error_sticky, output logic poisoned。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic [7:0] error_sticky, output logic poisoned,
    // 接口声明：output logic [3:0] m_awid, output logic [31:0] m_awaddr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [3:0] m_awid, output logic [31:0] m_awaddr,
    // 接口声明：output logic [7:0] m_awlen, output logic [2:0] m_awsize。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [7:0] m_awlen, output logic [2:0] m_awsize,
    // 接口声明：output logic [1:0] m_awburst, output logic m_awvalid, input logic m_awready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic [1:0] m_awburst, output logic m_awvalid, input logic m_awready,
    // 接口声明：output logic [127:0] m_wdata, output logic [15:0] m_wstrb。
    // 按字节选择本次写入生效的 lane。
    output logic [127:0] m_wdata, output logic [15:0] m_wstrb,
    // 接口声明：output logic m_wlast, m_wvalid, input logic m_wready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic m_wlast, m_wvalid, input logic m_wready,
    input logic [3:0] m_bid, input logic [1:0] m_bresp,
    input logic m_bvalid, output logic m_bready,
    output logic [3:0] m_arid, output logic [31:0] m_araddr,
    output logic [7:0] m_arlen, output logic [2:0] m_arsize,
    output logic [1:0] m_arburst, output logic m_arvalid, input logic m_arready,
    input logic [3:0] m_rid, input logic [127:0] m_rdata,
    input logic [1:0] m_rresp, input logic m_rlast, m_rvalid,
    output logic m_rready
);
    timeunit 1ns; timeprecision 1ps;
    typedef enum logic [2:0] {R_IDLE,R_ADDR,R_DATA,R_DRAIN} rstate_t;
    typedef enum logic [1:0] {W_COLLECT,W_ADDR,W_DATA,W_RESP} wstate_t;
    rstate_t rstate;
    wstate_t wstate;
    logic [127:0] cache_data[0:15], write_data[0:15];
    logic cache_valid, read_poison, write_poison, finish_q;
    logic [21:0] cache_tag;
    logic [29:0] read_addr_q, write_base_q;
    logic [3:0] read_index_q, write_index_q;
    logic [4:0] write_count_q;
    logic [7:0] read_error, write_error;
    wire read_address_ok = rd_addr[3:0]==0 && {1'b0,rd_addr}<DDR_BYTES;
    wire write_address_ok = wr_addr[3:0]==0 && {1'b0,wr_addr}<DDR_BYTES;
    wire write_contiguous = wr_addr==write_base_q+{21'd0,write_count_q,4'd0};
    wire read_fire = rd_valid && rd_ready;
    wire write_fire = wr_valid && wr_ready;

    assign poisoned = read_poison || write_poison;
    assign error_sticky = read_error | write_error;
    assign rd_ready = !rst && !frame_start && rstate==R_IDLE && !rsp_valid;
    assign wr_ready = !rst && !frame_start && wstate==W_COLLECT &&
        (poisoned || write_count_q==0 || (write_count_q<16 && write_contiguous));
    assign idle = !rst && rstate==R_IDLE && !rsp_valid &&
        wstate==W_COLLECT && write_count_q==0;
    assign drained = finish_q && idle;
    assign m_arid = AXI_ID;
    assign m_araddr = DDR_BASE+{2'd0,read_addr_q[29:8],8'd0};
    assign m_arlen = 8'd15;
    assign m_arsize = 3'd4;
    assign m_arburst = 2'b01;
    assign m_arvalid = !rst && rstate==R_ADDR;
    assign m_rready = !rst && (rstate==R_DATA || rstate==R_DRAIN);
    assign m_awid = AXI_ID;
    assign m_awaddr = DDR_BASE+{2'd0,write_base_q};
    assign m_awlen = 8'(write_count_q-1'b1);
    assign m_awsize = 3'd4;
    assign m_awburst = 2'b01;
    assign m_awvalid = !rst && wstate==W_ADDR;
    assign m_wdata = write_data[write_index_q];
    assign m_wstrb = 16'hffff;
    assign m_wlast = {1'b0,write_index_q}+5'd1==write_count_q;
    assign m_wvalid = !rst && wstate==W_DATA;
    assign m_bready = !rst && wstate==W_RESP;

    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst) begin
            finish_q<=0;
        end else begin
            if(frame_start) finish_q<=0;
            if(frame_finish) finish_q<=1;
        end
    end
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst) begin
            rstate<=R_IDLE; cache_valid<=0; cache_tag<=0;
            read_addr_q<=0; read_index_q<=0;
            rsp_valid<=0; rsp_data<=0; read_error<=0; read_poison<=0;
        end else begin
            if(frame_start) begin cache_valid<=0; read_error<=0; end
            // 握手/背压判断：rsp_valid && rsp_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if(rsp_valid && rsp_ready) rsp_valid<=0;
            // 按 rstate 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case(rstate)
                // 状态/选择分支 R_IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                R_IDLE: if(read_fire) begin
                    read_addr_q<=rd_addr;
                    if(!read_address_ok || poisoned) begin
                        rsp_valid<=1; rsp_data<=0;
                        if(!read_address_ok) read_error[0]<=1;
                    end else if(cache_valid && cache_tag==rd_addr[29:8]) begin
                        rsp_valid<=1; rsp_data<=cache_data[rd_addr[7:4]];
                    end else begin
                        cache_valid<=0; read_index_q<=0; rstate<=R_ADDR;
                    end
                end
                // 状态/选择分支 R_ADDR：本分支规定该编码下的寄存器更新和下一步动作。
                R_ADDR: if(m_arready) rstate<=R_DATA;
                // 状态/选择分支 R_DATA：本分支规定该编码下的寄存器更新和下一步动作。
                R_DATA: if(m_rvalid) begin
                    cache_data[read_index_q]<=m_rdata;
                    if(m_rresp!=0) read_error[1]<=1;
                    if(m_rid!=AXI_ID || m_rlast!=(read_index_q==15)) begin
                        read_error[2]<=1; read_poison<=1; cache_valid<=0;
                    end
                    if(m_rlast) begin
                        if(read_index_q==15 && m_rid==AXI_ID && !poisoned) begin
                            cache_valid<=1; cache_tag<=read_addr_q[29:8];
                            rsp_data<=read_addr_q[7:4]==15 ? m_rdata :
                                      cache_data[read_addr_q[7:4]];
                        end else rsp_data<=0;
                        rsp_valid<=1; rstate<=R_IDLE;
                    end else if(read_index_q==15) begin
                        rstate<=R_DRAIN;
                    end else read_index_q<=read_index_q+1'b1;
                end
                // 状态/选择分支 R_DRAIN：本分支规定该编码下的寄存器更新和下一步动作。
                R_DRAIN: if(m_rvalid && m_rlast) begin
                    rsp_data<=0; rsp_valid<=1; rstate<=R_IDLE;
                end
                default: rstate<=R_IDLE;
            endcase
        end
    end
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst) begin
            wstate<=W_COLLECT; write_base_q<=0; write_index_q<=0;
            write_count_q<=0; write_error<=0; write_poison<=0;
        end else begin
            if(frame_start) write_error<=0;
            // 按 wstate 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case(wstate)
                // 状态/选择分支 W_COLLECT：本分支规定该编码下的寄存器更新和下一步动作。
                W_COLLECT: begin
                    if(poisoned) write_count_q<=0;
                    else if(write_count_q!=0 &&
                        (finish_q || frame_finish || (wr_valid && !write_contiguous))) begin
                        write_index_q<=0; wstate<=W_ADDR;
                    end
                    if(write_fire) begin
                        if(!write_address_ok) write_error[0]<=1;
                        else if(!poisoned) begin
                            if(write_count_q==0) write_base_q<=wr_addr;
                            write_data[write_count_q[3:0]]<=wr_data;
                            write_count_q<=write_count_q+1'b1;
                            // The beat at 0xff0 must end its burst. A burst
                            // may start on any 16-byte boundary, including
                            // the last beat before a 4 KiB boundary.
                            if(write_count_q==15 || wr_addr[11:4]==8'hff) begin
                                write_index_q<=0; wstate<=W_ADDR;
                            end
                        end
                    end
                end
                // 状态/选择分支 W_ADDR：本分支规定该编码下的寄存器更新和下一步动作。
                W_ADDR: if(m_awready) begin write_index_q<=0; wstate<=W_DATA; end
                // 状态/选择分支 W_DATA：本分支规定该编码下的寄存器更新和下一步动作。
                W_DATA: if(m_wready) begin
                    if(m_wlast) wstate<=W_RESP;
                    else write_index_q<=write_index_q+1'b1;
                end
                // 状态/选择分支 W_RESP：本分支规定该编码下的寄存器更新和下一步动作。
                W_RESP: if(m_bvalid) begin
                    if(m_bresp!=0) write_error[3]<=1;
                    if(m_bid!=AXI_ID) begin write_error[4]<=1; write_poison<=1; end
                    write_count_q<=0; wstate<=W_COLLECT;
                end
                default: wstate<=W_COLLECT;
            endcase
        end
    end
endmodule
