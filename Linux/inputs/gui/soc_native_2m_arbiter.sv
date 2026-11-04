`timescale 1ns/1ps
// Two native 128-bit clients share the existing one-outstanding AXI adapter.
// Client 1 is time-sensitive video. When both request continuously it receives
// four transactions followed by one CPU transaction; CPU cannot starve.
// Ownership is retained through the response handshake, including errors.
// 双主仲裁器让 CPU 与显示 DMA 共享 DDR 请求和响应端口。
// 持续竞争时按视频四次 CPU 一次的规则分配，保护显示供数并保留 CPU 前进机会。
// 已接受请求的所有者必须一直跟随响应，不能按下一周期的仲裁选择回送数据。
// 写事务与读事务的应答类型不同，标签和错误位都随所有者传递。
// 仲裁次数是事务粒度配额，不能直接当成应用可用字节带宽的实测比例。
module soc_native_2m_arbiter(
    input logic clk,rst,
    // s_req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    input logic [1:0] s_req_valid,output logic [1:0] s_req_ready,
    input logic [1:0] s_req_write,
    // s_req_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
    input logic [1:0][31:0] s_req_addr,
    // s_req_wdata 保存写数据 payload，只有对应写请求被接受后才产生副作用。
    input logic [1:0][127:0] s_req_wdata,
    // s_req_wstrb 保存逐字节写使能，未使能的字节保持原值。
    input logic [1:0][15:0] s_req_wstrb,
    input logic [1:0][3:0] s_req_id,
    // s_rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output logic [1:0] s_rsp_valid,input logic [1:0] s_rsp_ready,
    output logic [1:0] s_rsp_write,
    output logic [1:0][3:0] s_rsp_id,
    // s_rsp_rdata 保存读响应 payload，须在响应有效时才能使用。
    output logic [1:0][127:0] s_rsp_rdata,
    // s_rsp_error 保存访问或译码错误标志，不能被正常数据值掩盖。
    output logic [1:0] s_rsp_error,
    // m_req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output logic m_req_valid,input logic m_req_ready,
    // m_req_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
    output logic m_req_write,output logic [31:0] m_req_addr,
    // m_req_wdata 保存写数据 payload，只有对应写请求被接受后才产生副作用。
    output logic [127:0] m_req_wdata,output logic [15:0] m_req_wstrb,
    output logic [3:0] m_req_id,
    // m_rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    input logic m_rsp_valid,output logic m_rsp_ready,
    input logic m_rsp_write,input logic [3:0] m_rsp_id,
    // m_rsp_rdata 保存读响应 payload，须在响应有效时才能使用。
    input logic [127:0] m_rsp_rdata,input logic m_rsp_error
);
    logic waiting_q,owner_q,chosen;
    logic [2:0] video_streak_q;
    // The pixel domain runs at 27 MHz versus 93.75 MHz DDR UI. A returned
    // response needs several slower pixel clocks to generate the next request.
    logic [5:0] video_guard_q;
    logic request_locked_q,request_owner_q;
    always_comb begin
        // chosen 按 request_locked_q 进行来源选择。
        // 真分支取 request_owner_q；其余情况取 1'b0。
        chosen=request_locked_q?request_owner_q:1'b0;
        if(!request_locked_q)begin
            if(s_req_valid[1] && (!s_req_valid[0] || video_streak_q<4))chosen=1'b1;
            else chosen=1'b0;
        end
        m_req_valid=0;m_req_write=0;m_req_addr=0;m_req_wdata=0;
        m_req_wstrb=0;m_req_id=0;m_rsp_ready=0;
        s_req_ready='0;s_rsp_valid='0;s_rsp_write='0;
        s_rsp_id='0;s_rsp_rdata='0;s_rsp_error='0;
        if(!rst && !waiting_q && !(video_guard_q!=0 && video_streak_q<4 && !s_req_valid[1]))begin
            // m_req_valid 读取 s_req_valid[chosen] 所选位域；位索引按声明中的高低位顺序解释。
            m_req_valid=s_req_valid[chosen];
            // m_req_write 读取 s_req_write[chosen] 所选位域；位索引按声明中的高低位顺序解释。
            m_req_write=s_req_write[chosen];
            // m_req_addr 读取 s_req_addr[chosen] 所选位域；位索引按声明中的高低位顺序解释。
            m_req_addr=s_req_addr[chosen];
            // m_req_wdata 读取 s_req_wdata[chosen] 所选位域；位索引按声明中的高低位顺序解释。
            m_req_wdata=s_req_wdata[chosen];
            // m_req_wstrb 读取 s_req_wstrb[chosen] 所选位域；位索引按声明中的高低位顺序解释。
            m_req_wstrb=s_req_wstrb[chosen];
            // m_req_id 读取 s_req_id[chosen] 所选位域；位索引按声明中的高低位顺序解释。
            m_req_id=s_req_id[chosen];
            s_req_ready[chosen]=m_req_ready;
        end else if(!rst)begin
            s_rsp_valid[owner_q]=m_rsp_valid;
            s_rsp_write[owner_q]=m_rsp_write;
            s_rsp_id[owner_q]=m_rsp_id;
            s_rsp_rdata[owner_q]=m_rsp_rdata;
            s_rsp_error[owner_q]=m_rsp_error;
            m_rsp_ready=s_rsp_ready[owner_q];
        end
    end
    always_ff @(posedge clk)begin
        if(rst)begin
            waiting_q<=0;owner_q<=0;video_streak_q<=0;video_guard_q<=0;
            request_locked_q<=0;request_owner_q<=0;
        end
        else if(!waiting_q)begin
            if(video_guard_q!=0)video_guard_q<=video_guard_q-1'b1;
            // 本分支处理握手条件 m_req_valid 与 m_req_ready；仅满足当前条件时推进下述事务。
            if(m_req_valid && m_req_ready)begin
                owner_q<=chosen;waiting_q<=1;request_locked_q<=0;
            end else if(m_req_valid)begin
                // A newly arriving preferred client must not change a
                // request already presented to a stalled downstream port.
                request_locked_q<=1;request_owner_q<=chosen;
            end
        // 本分支处理握手条件 m_rsp_valid 与 m_rsp_ready；仅满足当前条件时推进下述事务。
        end else if(m_rsp_valid && m_rsp_ready)begin
            waiting_q<=0;
            if(owner_q)begin
                if(video_streak_q<4)video_streak_q<=video_streak_q+1'b1;
                video_guard_q<=32;
            end else begin video_streak_q<=0;video_guard_q<=0;end
        end
    end
endmodule
