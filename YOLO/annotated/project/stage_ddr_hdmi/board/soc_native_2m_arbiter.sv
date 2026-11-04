// 架构导读：soc_native_2m_arbiter。
// 两主机本地内存请求仲裁，并把应答送回原请求方。
`timescale 1ns/1ps
// Two native 128-bit clients share the existing one-outstanding AXI adapter.
// Ownership is retained through the response handshake, including errors.
module soc_native_2m_arbiter #(
    // 静态配置：parameter bit BURST_ENABLE=1'b0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit BURST_ENABLE=1'b0
)(
    // 接口声明：input logic clk,rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input logic clk,rst,
    // 接口声明：input logic [1:0] s_req_valid,output logic [1:0] s_req_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic [1:0] s_req_valid,output logic [1:0] s_req_ready,
    // 接口声明：input logic [1:0] s_req_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [1:0] s_req_write,
    // 接口声明：input logic [1:0][31:0] s_req_addr。
    input logic [1:0][31:0] s_req_addr,
    input logic [1:0][127:0] s_req_wdata,
    input logic [1:0][15:0] s_req_wstrb,
    input logic [1:0][3:0] s_req_id,
    input logic [1:0][3:0] s_req_len,
    output logic [1:0] s_rsp_valid,input logic [1:0] s_rsp_ready,
    output logic [1:0] s_rsp_write,
    output logic [1:0][3:0] s_rsp_id,
    output logic [1:0][127:0] s_rsp_rdata,
    output logic [1:0] s_rsp_error,
    output logic m_req_valid,input logic m_req_ready,
    output logic m_req_write,output logic [31:0] m_req_addr,
    output logic [127:0] m_req_wdata,output logic [15:0] m_req_wstrb,
    output logic [3:0] m_req_id,output logic [3:0] m_req_len,
    input logic m_rsp_valid,input logic m_rsp_last,output logic m_rsp_ready,
    output logic [1:0] s_rsp_last,
    input logic m_rsp_write,input logic [3:0] m_rsp_id,
    input logic [127:0] m_rsp_rdata,input logic m_rsp_error
);
    logic waiting_q,owner_q,prefer_q,chosen;
    logic [3:0] write_remaining;
    logic request_locked_q,request_owner_q;
    // Separate request choice, request routing and response routing. This
    // preserves the combinational equations and avoids artificial scheduling
    // cycles between independent ready/valid channels in RTL simulators.
    always_comb begin
        chosen=request_locked_q?request_owner_q:prefer_q;
        if(!request_locked_q && !s_req_valid[prefer_q] && s_req_valid[!prefer_q])
            chosen=!prefer_q;
    end
    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        m_req_valid=0;m_req_write=0;m_req_addr=0;m_req_wdata=0;
        m_req_wstrb=0;m_req_id=0;m_req_len=0;s_req_ready='0;
        // 复位相关判断：!rst && !waiting_q；分支方向由信号极性与取反表达式决定。
        if(!rst && !waiting_q)begin
            m_req_valid=s_req_valid[chosen];
            m_req_write=s_req_write[chosen];
            m_req_addr=s_req_addr[chosen];
            m_req_wdata=s_req_wdata[chosen];
            m_req_wstrb=s_req_wstrb[chosen];
            m_req_id=s_req_id[chosen];
            m_req_len=BURST_ENABLE?s_req_len[chosen]:4'd0;
            s_req_ready[chosen]=m_req_ready;
        // 复位相关判断：!rst&&waiting_q&&write_remaining!=0；分支方向由信号极性与取反表达式决定。
        end else if(!rst&&waiting_q&&write_remaining!=0)begin
            // Continuation beats belong to the accepted write packet, never
            // to a newly arriving contender. One response follows its real B.
            m_req_valid=s_req_valid[owner_q];m_req_write=s_req_write[owner_q];
            m_req_addr=s_req_addr[owner_q];m_req_wdata=s_req_wdata[owner_q];
            m_req_wstrb=s_req_wstrb[owner_q];m_req_id=s_req_id[owner_q];
            m_req_len=s_req_len[owner_q];s_req_ready[owner_q]=m_req_ready;
        end
    end
    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        m_rsp_ready=0;
        s_rsp_valid='0;s_rsp_write='0;s_rsp_last='0;
        s_rsp_id='0;s_rsp_rdata='0;s_rsp_error='0;
        // 复位相关判断：!rst && !waiting_q；分支方向由信号极性与取反表达式决定。
        if(!rst && !waiting_q)begin
            // Request phase: no response is exposed.
        end else if(!rst)begin
            s_rsp_valid[owner_q]=m_rsp_valid;
            s_rsp_last[owner_q]=!BURST_ENABLE||m_rsp_last;
            s_rsp_write[owner_q]=m_rsp_write;
            s_rsp_id[owner_q]=m_rsp_id;
            s_rsp_rdata[owner_q]=m_rsp_rdata;
            s_rsp_error[owner_q]=m_rsp_error;
            m_rsp_ready=s_rsp_ready[owner_q];
        end
    end
    // 过程边界：always_ff @(posedge clk)begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk)begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst)begin
            waiting_q<=0;owner_q<=0;prefer_q<=0;write_remaining<=0;
            request_locked_q<=0;request_owner_q<=0;
        end
        else if(!waiting_q)begin
            // 握手/背压判断：m_req_valid && m_req_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if(m_req_valid && m_req_ready)begin
                owner_q<=chosen;waiting_q<=1;request_locked_q<=0;
                write_remaining<=BURST_ENABLE&&m_req_write?m_req_len:4'd0;
            end else if(m_req_valid)begin
                // A newly arriving preferred client must not change a
                // request already presented to a stalled downstream port.
                request_locked_q<=1;request_owner_q<=chosen;
            end
        end else if(write_remaining!=0)begin
            // 握手/背压判断：m_req_valid&&m_req_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if(m_req_valid&&m_req_ready)write_remaining<=write_remaining-1'b1;
        // 握手/背压判断：m_rsp_valid && m_rsp_ready && (!BURST_ENABLE||m_rsp_last)。
        // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
        end else if(m_rsp_valid && m_rsp_ready && (!BURST_ENABLE||m_rsp_last))begin
            waiting_q<=0;prefer_q<=!owner_q;
        end
    end
endmodule
