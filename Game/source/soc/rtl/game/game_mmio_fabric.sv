// [ARCH] 按键和视频窗口接入 CPU MMIO 请求/响应总线。
// [ARCH] 解码偏移与 game_regs.h 保持一致。
// [ARCH] 一个请求只能由一个目标响应，未命中不伪造成合法设备。
// [ARCH] 等待时保持窗口选择与原请求关联。
// ---------------------------------------------------------------------------
// game_mmio_fabric -- two-slave, single-owner splitter for the game board
// window at 0x6000_1000..0x6000_1fff.
//
//   page 0x0  game_input     (CPU clock domain)
//   page 0x1  game_video_ctrl (DDR user clock domain, behind pg_mmio_cdc)
//   others    local SLVERR response, never a hang
//
// One request is outstanding at a time and the owner is held until its
// response handshake completes.  A response from any non-owner is ignored,
// which keeps a mis-decoded slave from corrupting an unrelated transaction.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
module game_mmio_fabric (
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input  logic clk,
    // [ARCH] rst：复位控制不同于 PLL/DDR 就绪；具体极性与同步方式按本模块时序块执行。
    input  logic rst,
    // [ARCH] req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_req_valid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic req_valid,
    // [ARCH] req_ready：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    output logic req_ready,
    // [ARCH] req_addr：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 error_hit, select_onehot, m_req_addr, req_ready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic [31:0] req_addr,
    // [ARCH] req_write：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_req_write 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic req_write,
    // [ARCH] req_wdata：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_req_wdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic [31:0] req_wdata,
    // [ARCH] req_is_fetch：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 error_hit 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic req_is_fetch,
    // [ARCH] req_wstrb：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_req_wstrb 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic [3:0]  req_wstrb,
    // [ARCH] rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    output logic rsp_valid,
    // [ARCH] rsp_ready：就绪/接纳资格需按当前接口或候选逻辑解释；操作数准备位与总线握手 ready 不能混为一类。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_rsp_ready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic rsp_ready,
    // [ARCH] rsp_rdata：读返回值只有在对应响应有效时可消费，并需检查错误归属。
    output logic [31:0] rsp_rdata,
    // [ARCH] rsp_error：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    output logic rsp_error,
    // [ARCH] m_req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    output logic [1:0] m_req_valid,
    // [ARCH] m_req_ready：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 req_ready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic [1:0] m_req_ready,
    // [ARCH] m_req_addr：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    output logic [31:0] m_req_addr,
    // [ARCH] m_req_write：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    output logic m_req_write,
    // [ARCH] m_req_wdata：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    output logic [31:0] m_req_wdata,
    // [ARCH] m_req_wstrb：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    output logic [3:0]  m_req_wstrb,
    // [ARCH] m_rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_valid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic [1:0] m_rsp_valid,
    // [ARCH] m_rsp_ready：就绪/接纳资格需按当前接口或候选逻辑解释；操作数准备位与总线握手 ready 不能混为一类。
    output logic [1:0] m_rsp_ready,
    // [ARCH] m_rsp_rdata：读返回值只有在对应响应有效时可消费，并需检查错误归属。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_rdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic [1:0][31:0] m_rsp_rdata,
    // [ARCH] m_rsp_error：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_error 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic [1:0] m_rsp_error
);
    timeunit 1ns;
    timeprecision 1ps;

    logic busy_q;
    // [ARCH] owner_q：选择真正拥有当前有效结果的银行/事务，不能依赖 RAM 最后看到的值。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_valid, rsp_error, rsp_rdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic owner_q;
    // [ARCH] error_hit_q：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_valid, rsp_error, rsp_rdata, m_rsp_ready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic error_hit_q;
    // [ARCH] error_hit：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 select_onehot, m_req_valid, req_ready, error_hit_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic error_hit;
    logic [1:0] select_onehot;
    // [ARCH] error_rdata：读返回值只有在对应响应有效时可消费，并需检查错误归属。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_rdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [31:0] error_rdata;

    assign error_hit = (req_addr[11:8] > 4'h1) || req_is_fetch;
    assign select_onehot = error_hit ? 2'b00 : (req_addr[11:8] == 4'h0 ? 2'b01 : 2'b10);

    assign m_req_addr = req_addr;
    assign m_req_write = req_write;
    assign m_req_wdata = req_wdata;
    assign m_req_wstrb = req_wstrb;

    assign m_req_valid = (!rst && !busy_q && req_valid && !error_hit) ? select_onehot : 2'b00;
    assign req_ready = !rst && !busy_q && (error_hit ? 1'b1 : m_req_ready[req_addr[8]]);

    // A slave may take many cycles to respond, especially across the video
    // clock-domain bridge.  Keep the accepted owner and local-error decision
    // until a real response is consumed; the upstream request bus may already
    // have changed by then.
    assign rsp_valid = !rst && busy_q && (error_hit_q || m_rsp_valid[owner_q]);
    assign rsp_error = busy_q ? (error_hit_q ? 1'b1 : m_rsp_error[owner_q]) : 1'b0;
    assign rsp_rdata = busy_q ? (error_hit_q ? error_rdata : m_rsp_rdata[owner_q]) : 32'd0;

    assign m_rsp_ready = (!rst && busy_q && !error_hit_q && rsp_ready) ?
                         (owner_q ? 2'b10 : 2'b01) : 2'b00;

    always_ff @(posedge clk) begin
        if (rst) begin
            busy_q <= 1'b0;
            owner_q <= 1'b0;
            error_hit_q <= 1'b0;
            error_rdata <= 32'h0BAD_0000;
        end else if (req_valid && req_ready) begin
            busy_q <= 1'b1;
            owner_q <= req_addr[8];
            error_hit_q <= error_hit;
            error_rdata <= 32'h0BAD_0000 | {28'd0, req_addr[11:8]};
        end else if (rsp_valid && rsp_ready) begin
            busy_q <= 1'b0;
        end
    end

endmodule
