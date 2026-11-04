// F SoC AXI128 -> HMIC_S 1.16a Standard AXI256.
// One physical burst at a time. A second logical command can be staged while
// the first B/R response is held by the upstream AXI master.
// Buffer the entire read burst: vendor UG042003 p36/p45 requires RREADY=1
// whenever RVALID=1. 16 logical beats starting in the upper half need 9
// physical beats. Byte addresses are rebased, NOT divided as in reduced AXI.
// Reset must reset the controller too; fault is sticky until this common reset.
// 此适配器把板级请求转换为 DDR 控制器 AXI 接口，保留地址 数据与响应的阶段关系。
// 写地址和写数据独立握手，B 响应完成后才可报告该写事务结束。
// 读地址接受后等待带身份的读响应，错误与末拍属性必须被检查和传播。
// 故障保护阻止已失配事务继续污染后续请求，复位前不能伪装成正常完成。
// 实际并发深度以状态机和 outstanding 约束为准，AXI 总线名称不代表无限并发。
module soc_hmic_axi_adapter #(
    parameter logic [31:0] DDR_BASE=32'h80000000,
    parameter logic [32:0] DDR_BYTES=33'h010000000,
    // WATCHDOG_CYCLES 定义协议等待看门狗阈值，用于把卡死事务转成明确故障。
    parameter int WATCHDOG_CYCLES=65536
)(
    // ddr_ready 保存接收或操作数就绪资格，须结合对应的有效位使用。
    input logic clk,rst,ddr_ready,
    // protocol_fault 保存异常资格，须携带对应指令或请求身份交给后续处理。
    output logic protocol_fault,
    // s_awid 是 AXI 写地址通道的事务身份，响应需要返回给对应请求所有者。
    // 该通道只有在 valid 与 ready 同时成立时才完成一次实际传递。
    input logic [3:0] s_awid,
    // s_awaddr 是 AXI 写地址通道的字节地址，控制器侧还会按其地址窗进行重定位。
    input logic [31:0] s_awaddr,
    // s_awlen 是 AXI 写地址通道的突发拍数减一，不能直接把编码值当作实际拍数。
    input logic [7:0] s_awlen,
    // s_awsize 是 AXI 写地址通道的每拍字节数的二进制指数编码。
    input logic [2:0] s_awsize,
    // s_awburst 是 AXI 写地址通道的突发地址递增方式。
    input logic [1:0] s_awburst,
    // s_awvalid 是 AXI 写地址通道的本通道当前存在有效 payload 的资格。
    input logic s_awvalid,
    // s_awready 是 AXI 写地址通道的接收方本拍能够接收该通道 payload 的资格。
    output logic s_awready,
    // s_wdata 保存写数据 payload，只有对应写请求被接受后才产生副作用。
    input logic [127:0] s_wdata,
    // s_wstrb 保存逐字节写使能，未使能的字节保持原值。
    input logic [15:0] s_wstrb,
    // s_wlast 是 AXI 写数据通道的当前为本突发最后一个数据拍的标记。
    input logic s_wlast,s_wvalid,
    // s_wready 是 AXI 写数据通道的接收方本拍能够接收该通道 payload 的资格。
    output logic s_wready,
    // s_bid 是 AXI 写响应通道的事务身份，响应需要返回给对应请求所有者。
    output logic [3:0] s_bid,
    // s_bresp 是 AXI 写响应通道的本次访问的成功或错误响应编码。
    output logic [1:0] s_bresp,
    // s_bvalid 是 AXI 写响应通道的本通道当前存在有效 payload 的资格。
    output logic s_bvalid,
    // s_bready 是 AXI 写响应通道的接收方本拍能够接收该通道 payload 的资格。
    input logic s_bready,
    // s_arid 是 AXI 读地址通道的事务身份，响应需要返回给对应请求所有者。
    input logic [3:0] s_arid,
    // s_araddr 是 AXI 读地址通道的字节地址，控制器侧还会按其地址窗进行重定位。
    input logic [31:0] s_araddr,
    // s_arlen 是 AXI 读地址通道的突发拍数减一，不能直接把编码值当作实际拍数。
    input logic [7:0] s_arlen,
    // s_arsize 是 AXI 读地址通道的每拍字节数的二进制指数编码。
    input logic [2:0] s_arsize,
    // s_arburst 是 AXI 读地址通道的突发地址递增方式。
    input logic [1:0] s_arburst,
    // s_arvalid 是 AXI 读地址通道的本通道当前存在有效 payload 的资格。
    input logic s_arvalid,
    // s_arready 是 AXI 读地址通道的接收方本拍能够接收该通道 payload 的资格。
    output logic s_arready,
    // s_rid 是 AXI 读响应通道的事务身份，响应需要返回给对应请求所有者。
    output logic [3:0] s_rid,
    // s_rdata 保存读响应 payload，须在响应有效时才能使用。
    output logic [127:0] s_rdata,
    // s_rresp 是 AXI 读响应通道的本次访问的成功或错误响应编码。
    output logic [1:0] s_rresp,
    // s_rlast 是 AXI 读响应通道的当前为本突发最后一个数据拍的标记。
    output logic s_rlast,s_rvalid,
    // s_rready 是 AXI 读响应通道的接收方本拍能够接收该通道 payload 的资格。
    input logic s_rready,
    // m_awid 是 AXI 写地址通道的事务身份，响应需要返回给对应请求所有者。
    output logic [7:0] m_awid,
    // m_awaddr 是 AXI 写地址通道的字节地址，控制器侧还会按其地址窗进行重定位。
    output logic [29:0] m_awaddr,
    // m_awlen 是 AXI 写地址通道的突发拍数减一，不能直接把编码值当作实际拍数。
    output logic [7:0] m_awlen,
    // m_awsize 是 AXI 写地址通道的每拍字节数的二进制指数编码。
    output logic [2:0] m_awsize,
    // m_awburst 是 AXI 写地址通道的突发地址递增方式。
    output logic [1:0] m_awburst,
    // m_awvalid 是 AXI 写地址通道的本通道当前存在有效 payload 的资格。
    output logic m_awvalid,
    // m_awready 是 AXI 写地址通道的接收方本拍能够接收该通道 payload 的资格。
    input logic m_awready,
    // m_wdata 保存写数据 payload，只有对应写请求被接受后才产生副作用。
    output logic [255:0] m_wdata,
    // m_wstrb 保存逐字节写使能，未使能的字节保持原值。
    output logic [31:0] m_wstrb,
    // m_wlast 是 AXI 写数据通道的当前为本突发最后一个数据拍的标记。
    output logic m_wlast,m_wvalid,
    // m_wready 是 AXI 写数据通道的接收方本拍能够接收该通道 payload 的资格。
    input logic m_wready,
    // m_bid 是 AXI 写响应通道的事务身份，响应需要返回给对应请求所有者。
    input logic [7:0] m_bid,
    // m_bresp 是 AXI 写响应通道的本次访问的成功或错误响应编码。
    input logic [1:0] m_bresp,
    // m_bvalid 是 AXI 写响应通道的本通道当前存在有效 payload 的资格。
    input logic m_bvalid,
    // m_bready 是 AXI 写响应通道的接收方本拍能够接收该通道 payload 的资格。
    output logic m_bready,
    // m_arid 是 AXI 读地址通道的事务身份，响应需要返回给对应请求所有者。
    output logic [7:0] m_arid,
    // m_araddr 是 AXI 读地址通道的字节地址，控制器侧还会按其地址窗进行重定位。
    output logic [29:0] m_araddr,
    // m_arlen 是 AXI 读地址通道的突发拍数减一，不能直接把编码值当作实际拍数。
    output logic [7:0] m_arlen,
    // m_arsize 是 AXI 读地址通道的每拍字节数的二进制指数编码。
    output logic [2:0] m_arsize,
    // m_arburst 是 AXI 读地址通道的突发地址递增方式。
    output logic [1:0] m_arburst,
    // m_arvalid 是 AXI 读地址通道的本通道当前存在有效 payload 的资格。
    output logic m_arvalid,
    // m_arready 是 AXI 读地址通道的接收方本拍能够接收该通道 payload 的资格。
    input logic m_arready,
    // m_rid 是 AXI 读响应通道的事务身份，响应需要返回给对应请求所有者。
    input logic [7:0] m_rid,
    // m_rdata 保存读响应 payload，须在响应有效时才能使用。
    input logic [255:0] m_rdata,
    // m_rresp 是 AXI 读响应通道的本次访问的成功或错误响应编码。
    input logic [1:0] m_rresp,
    // m_rlast 是 AXI 读响应通道的当前为本突发最后一个数据拍的标记。
    input logic m_rlast,m_rvalid,
    // m_rready 是 AXI 读响应通道的接收方本拍能够接收该通道 payload 的资格。
    output logic m_rready
);
    timeunit 1ns; timeprecision 1ps;
    localparam int WATCHDOG_W=$clog2(WATCHDOG_CYCLES);
    typedef enum logic [3:0] {IDLE,WCOLLECT,WADDR,WDATA,WRESP,BOUT,
                             RADDR,RDATA,ROUT,BADWRITE,BADREAD,FAULT,
                             RWAIT_PENDING} state_t;
    state_t state;
    typedef enum logic [2:0] {PNONE,PADDR,PDATA,PWC,PWADDR,PWDATA,PWRESP,PDONE} prefetch_t;
    prefetch_t prefetch_state;
    // One physical write bank is shared by both logical command slots.
    // A second write may fill a beat only after the first HMIC W beat has
    // been accepted, so arbitrary physical backpressure remains safe.
    logic [255:0] wdata_q[0:8];
    logic [255:0] rdata_q[0:1][0:8];
    logic [31:0] mask_q[0:8];
    logic [1:0] resp_q[0:1][0:8];
    logic [29:0] addr_q;
    logic [3:0] id_q;
    logic [8:0] logical_count_q,logical_index_q;
    logic [3:0] physical_count_q,physical_index_q;
    logic first_half_q,prefer_read_q;
    logic [1:0] bresp_q;
    logic [WATCHDOG_W-1:0] watchdog_q;
    logic active_bank,prefetch_valid,prefetch_bad,prefetch_write;
    logic [3:0] prefetch_id,prefetch_physical_count,prefetch_physical_index;
    // prefetch_logical_count 保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
    logic [8:0] prefetch_logical_count;
    // prefetch_logical_index 保存表或队列的索引，须配合有效位与对应所有者使用。
    logic [8:0] prefetch_logical_index;
    // prefetch_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
    logic [29:0] prefetch_addr;
    logic prefetch_first_half;
    logic [1:0] prefetch_bresp;
    // half_index 保存表或队列的索引，须配合有效位与对应所有者使用。
    // half_index 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {1'b0,logical_index_q}+10'(first_half_q)；复制大括号表示重复位域，不是独立队列元素。
    wire [9:0] half_index={1'b0,logical_index_q}+10'(first_half_q);
    // prefetch_half_index 保存表或队列的索引，须配合有效位与对应所有者使用。
    // prefetch_half_index 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {1'b0,prefetch_logical_index}+10'(prefetch_first_half)；复制大括号表示重复位域，不是独立队列元素。
    wire [9:0] prefetch_half_index={1'b0,prefetch_logical_index}+10'(prefetch_first_half);
    // data_read_index 属于D-cache 状态，保存表或队列的索引，须配合有效位与对应所有者使用。
    // 脏行替换必须先保留待写回数据，不能被新回填覆盖。
    // data_read_index 按 (state==ROUT) 进行来源选择。
    // 真分支取 half_index[4:1]；其余情况取 physical_index_q。
    wire [3:0] data_read_index=(state==ROUT)?half_index[4:1]:physical_index_q;
    wire [255:0] selected_data=rdata_q[active_bank][data_read_index];
    // write_fill_active 的资格组合为 state==WCOLLECT&&s_wvalid&&s_wready。
    // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
    wire write_fill_active=state==WCOLLECT&&s_wvalid&&s_wready;
    // write_fill_prefetch 的资格组合为 prefetch_state==PWC&&s_wvalid&&s_wready&&!prefetch_bad。
    wire write_fill_prefetch=prefetch_state==PWC&&s_wvalid&&s_wready&&!prefetch_bad;
    // write_fill_half 按 write_fill_active 进行来源选择。
    // 真分支取 half_index；其余情况取 prefetch_half_index。
    wire [9:0] write_fill_half=write_fill_active?half_index:prefetch_half_index;
    // clear_active_mask 的资格组合为 state==IDLE&&s_awvalid&&s_awready。
    wire clear_active_mask=state==IDLE&&s_awvalid&&s_awready;
    // read_fill_active 由比较式 state==RDATA 产生；该结果是条件判断，不是被比较的数据。
    wire read_fill_active=state==RDATA;
    // read_fill_prefetch 由比较式 prefetch_state==PDATA 产生；该结果是条件判断，不是被比较的数据。
    wire read_fill_prefetch=prefetch_state==PDATA;
    // read_fill_bank 按 read_fill_active 进行来源选择。
    // 真分支取 active_bank；其余情况取 ~active_bank。
    wire read_fill_bank=read_fill_active?active_bank:~active_bank;
    // read_fill_index 保存表或队列的索引，须配合有效位与对应所有者使用。
    // read_fill_index 按 read_fill_active 进行来源选择。
    // 真分支取 physical_index_q；其余情况取 prefetch_physical_index。
    wire [3:0] read_fill_index=read_fill_active?physical_index_q:prefetch_physical_index;
    // choose_read 的资格组合为 s_arvalid&&(!s_awvalid||prefer_read_q)。
    wire choose_read=s_arvalid&&(!s_awvalid||prefer_read_q);
    // final_read_fire 的资格组合为 (state==ROUT)&&s_rvalid&&s_rready&&s_rlast。
    wire final_read_fire=(state==ROUT)&&s_rvalid&&s_rready&&s_rlast;
    // final_write_fire 的资格组合为 (state==BOUT)&&s_bvalid&&s_bready。
    wire final_write_fire=(state==BOUT)&&s_bvalid&&s_bready;
    // offer_prefetch 的资格组合为 (state==WADDR||state==WDATA||state==WRESP|| state==RADDR||state==RDATA||state==ROUT||state==BOUT)&& !prefetch_valid&& !final_read_fire&&!final_write_fire。
    wire offer_prefetch=(state==WADDR||state==WDATA||state==WRESP||
                         // state 的资格组合为 =RADDR||state==RDATA||state==ROUT||state==BOUT)&&。
                         state==RADDR||state==RDATA||state==ROUT||state==BOUT)&&
                        !prefetch_valid&&
                        !final_read_fire&&!final_write_fire;
    // prefetch_issue_safe 的资格组合为 (state==ROUT||state==BOUT||state==RWAIT_PENDING)。
    wire prefetch_issue_safe=(state==ROUT||state==BOUT||state==RWAIT_PENDING);
    // write_slot_available 的资格组合为 (state==RADDR||state==RDATA||state==ROUT|| state==WRESP||state==BOUT||state==RWAIT_PENDING|| (state==WDATA&& prefetch_half_index[4:1]<physical_index_q))。
    wire write_slot_available=(state==RADDR||state==RDATA||state==ROUT||
                               // state 的资格组合为 =WRESP||state==BOUT||state==RWAIT_PENDING||。
                               state==WRESP||state==BOUT||state==RWAIT_PENDING||
                               (state==WDATA&&
                                prefetch_half_index[4:1]<physical_index_q));
    wire wait_controller=(state==WADDR||state==WDATA||state==WRESP||
                          // state 的资格组合为 =RADDR||state==RDATA||。
                          state==RADDR||state==RDATA||
                          // prefetch_state 的资格组合为 =PADDR||prefetch_state==PDATA||。
                          prefetch_state==PADDR||prefetch_state==PDATA||
                          // prefetch_state 的资格组合为 =PWADDR||prefetch_state==PWDATA||。
                          prefetch_state==PWADDR||prefetch_state==PWDATA||
                          prefetch_state==PWRESP);
    // controller_progress 的资格组合为 (m_awvalid&&m_awready)||(m_wvalid&&m_wready)|| (m_bvalid&&m_bready)||(m_arvalid&&m_arready)|| (m_rvalid&&(state==RDATA||prefetch_state==PDATA))。
    wire controller_progress=(m_awvalid&&m_awready)||(m_wvalid&&m_wready)||
                             (m_bvalid&&m_bready)||(m_arvalid&&m_arready)||
                             (m_rvalid&&(state==RDATA||prefetch_state==PDATA));
    function automatic logic legal(input logic [31:0] a,input logic [7:0] len,
                                   // size 保存访问尺寸编码，决定对齐和字节选择的处理方式。
                                   input logic [2:0] size,input logic [1:0] burst);
        logic [32:0] limit;
        // limit 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
        // 拼接源为 {1'b0,a}+((33'(len)+1)<<4)；复制大括号表示重复位域，不是独立队列元素。
        limit={1'b0,a}+((33'(len)+1)<<4);
        return len<16 && size==4 && burst==1 && a[3:0]==0 &&
               {1'b0,a}>={1'b0,DDR_BASE} && limit<=({1'b0,DDR_BASE}+DDR_BYTES) &&
               (33'(a[11:0])+((33'(len)+1)<<4)<=4096);
    endfunction
    // protocol_fault 由比较式 (state==FAULT) 产生；该结果是条件判断，不是被比较的数据。
    assign protocol_fault=(state==FAULT);
    // s_awready 的资格组合为 !rst&&ddr_ready&&。
    assign s_awready=!rst&&ddr_ready&&
                     ((state==IDLE&&!choose_read)||
                      (offer_prefetch&&s_awvalid&&!choose_read));
    // s_arready 的资格组合为 !rst&&ddr_ready&&。
    assign s_arready=!rst&&ddr_ready&&
                     ((state==IDLE&&choose_read)||
                      (offer_prefetch&&choose_read));
    // s_wready 的资格组合为 !rst&&(state==WCOLLECT||state==BADWRITE||。
    assign s_wready=!rst&&(state==WCOLLECT||state==BADWRITE||
                           (prefetch_state==PWC&&(prefetch_bad||write_slot_available)));
    // s_bid 连接到 id_q，两者在此路径上保持字段对应。
    assign s_bid=id_q;
    // s_bresp 连接到 bresp_q，两者在此路径上保持字段对应。
    assign s_bresp=bresp_q;
    // s_bvalid 的资格组合为 !rst&&state==BOUT。
    assign s_bvalid=!rst&&state==BOUT;
    // s_rid 连接到 id_q，两者在此路径上保持字段对应。
    assign s_rid=id_q;
    // s_rdata 按 selected_data[128*half_index[0]+:128] 计算，运算位宽与有无符号以原声明和显式扩展为准。
    assign s_rdata=selected_data[128*half_index[0]+:128];
    // s_rresp 按 (state==ROUT) 选择候选来源；各分支结果仍属于当前组合路径。
    // s_rresp 按 (state==ROUT) 进行来源选择。
    // 真分支取 resp_q[active_bank][half_index[4:1]]；其余情况取 2'b11。
    assign s_rresp=(state==ROUT)?resp_q[active_bank][half_index[4:1]]:2'b11;
    // s_rvalid 的资格组合为 !rst&&(state==ROUT||state==BADREAD)。
    assign s_rvalid=!rst&&(state==ROUT||state==BADREAD);
    // s_rlast 由比较式 logical_index_q+1==logical_count_q 产生；该结果是条件判断，不是被比较的数据。
    assign s_rlast=logical_index_q+1==logical_count_q;
    // m_awid 按 (state!=WADDR&&prefetch_state==PWADDR) 选择候选来源；各分支结果仍属于当前组合路径。
    // m_awid 按 (state!=WADDR&&prefetch_state==PWADDR) 进行来源选择。
    // 真分支取 {4'b0,prefetch_id}；其余情况取 {4'b0,id_q}。
    assign m_awid=(state!=WADDR&&prefetch_state==PWADDR)?{4'b0,prefetch_id}:{4'b0,id_q};
    // m_arid 按 (state!=RADDR&&prefetch_state==PADDR) 选择候选来源；各分支结果仍属于当前组合路径。
    assign m_arid=(state!=RADDR&&prefetch_state==PADDR)?{4'b0,prefetch_id}:{4'b0,id_q};
    // m_awaddr 按 (state!=WADDR&&prefetch_state==PWADDR) 选择候选来源；各分支结果仍属于当前组合路径。
    assign m_awaddr=(state!=WADDR&&prefetch_state==PWADDR)?prefetch_addr:addr_q;
    // m_araddr 按 (state!=RADDR&&prefetch_state==PADDR) 选择候选来源；各分支结果仍属于当前组合路径。
    assign m_araddr=(state!=RADDR&&prefetch_state==PADDR)?prefetch_addr:addr_q;
    // m_awlen 按 (state!=WADDR&&prefetch_state==PWADDR) 选择候选来源；各分支结果仍属于当前组合路径。
    assign m_awlen=(state!=WADDR&&prefetch_state==PWADDR)?8'(prefetch_physical_count)-1:
                   8'(physical_count_q)-1;
    // m_arlen 按 (state!=RADDR&&prefetch_state==PADDR) 选择候选来源；各分支结果仍属于当前组合路径。
    assign m_arlen=(state!=RADDR&&prefetch_state==PADDR)?8'(prefetch_physical_count)-1:
                   8'(physical_count_q)-1;
    assign m_awsize=5;
    assign m_arsize=5;
    assign m_awburst=1;
    assign m_arburst=1;
    assign m_awvalid=!rst&&ddr_ready&&
                     (state==WADDR||(prefetch_state==PWADDR&&prefetch_issue_safe));
    assign m_arvalid=!rst&&ddr_ready&&
                     (state==RADDR||(prefetch_state==PADDR&&prefetch_issue_safe));
    // m_wdata 按 (prefetch_state==PWDATA) 选择候选来源；各分支结果仍属于当前组合路径。
    assign m_wdata=(prefetch_state==PWDATA)?wdata_q[prefetch_physical_index]:
                   wdata_q[physical_index_q];
    // m_wstrb 按 (prefetch_state==PWDATA) 选择候选来源；各分支结果仍属于当前组合路径。
    assign m_wstrb=(prefetch_state==PWDATA)?mask_q[prefetch_physical_index]:
                   (state==WDATA)?mask_q[physical_index_q]:'0;
    // m_wlast 按 (prefetch_state==PWDATA) 选择候选来源；各分支结果仍属于当前组合路径。
    assign m_wlast=(prefetch_state==PWDATA)?
                   prefetch_physical_index+1==prefetch_physical_count:
                   physical_index_q+1==physical_count_q;
    assign m_wvalid=!rst&&ddr_ready&&(state==WDATA||prefetch_state==PWDATA);
    assign m_bready=!rst&&(state==WRESP||prefetch_state==PWRESP);
    // Not derived from CPU ready. Every issued read has 9 reserved RAM slots.
    assign m_rready=1'b1;
    initial begin
        if (DDR_BASE[4:0]!=0||DDR_BYTES[4:0]!=0||DDR_BYTES==0||DDR_BYTES>33'h040000000||
            {1'b0,DDR_BASE}+DDR_BYTES>33'h100000000||WATCHDOG_CYCLES<2)
            $fatal(1,"HMIC_ADAPTER_CONFIGURATION");
    end
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;addr_q<=0;id_q<=0;logical_count_q<=0;logical_index_q<=0;
            physical_count_q<=0;physical_index_q<=0;first_half_q<=0;
            bresp_q<=0;watchdog_q<=0;prefer_read_q<=0;
            active_bank<=0;prefetch_state<=PNONE;prefetch_valid<=0;prefetch_bad<=0;
            prefetch_write<=0;prefetch_logical_index<=0;prefetch_bresp<=0;
            prefetch_id<=0;prefetch_addr<=0;prefetch_logical_count<=0;
            prefetch_physical_count<=0;prefetch_physical_index<=0;
            prefetch_first_half<=0;
        end else begin
            if(!wait_controller||controller_progress)watchdog_q<=0;
            else watchdog_q<=watchdog_q+1'b1;
            case(state)
                IDLE:begin
                    logical_index_q<=0;physical_index_q<=0;
                    // 本分支处理握手条件 s_awvalid 与 s_awready；仅满足当前条件时推进下述事务。
                    if(s_awvalid&&s_awready)begin
                        id_q<=s_awid;logical_count_q<=9'(s_awlen)+1;first_half_q<=s_awaddr[4];
                        physical_count_q<=4'((10'(s_awlen)+10'd2+10'(s_awaddr[4]))>>1);
                        addr_q<=30'((s_awaddr-DDR_BASE)&32'hffffffe0);
                        bresp_q<=0;prefer_read_q<=1;
                        // state 按 legal(s_awaddr,s_awlen,s_awsize,s_awburst) 选择候选来源；各分支结果仍属于当前寄存边界。
                        state<=legal(s_awaddr,s_awlen,s_awsize,s_awburst)?WCOLLECT:BADWRITE;
                    // 本分支处理握手条件 s_arvalid 与 s_arready；仅满足当前条件时推进下述事务。
                    end else if(s_arvalid&&s_arready)begin
                        id_q<=s_arid;logical_count_q<=9'(s_arlen)+1;first_half_q<=s_araddr[4];
                        physical_count_q<=4'((10'(s_arlen)+10'd2+10'(s_araddr[4]))>>1);
                        addr_q<=30'((s_araddr-DDR_BASE)&32'hffffffe0);
                        prefer_read_q<=0;
                        // state 按 legal(s_araddr,s_arlen,s_arsize,s_arburst) 选择候选来源；各分支结果仍属于当前寄存边界。
                        state<=legal(s_araddr,s_arlen,s_arsize,s_arburst)?RADDR:BADREAD;
                    end
                end
                WCOLLECT,BADWRITE:if(s_wvalid&&s_wready)begin
                    if(state==WCOLLECT)begin
                    end
                    logical_index_q<=logical_index_q+1'b1;
                    if(s_wlast!=(logical_index_q+1==logical_count_q))state<=FAULT;
                    else if(s_wlast)begin
                        if(state==BADWRITE)begin state<=BOUT;bresp_q<=2'b11;end
                        else state<=WADDR;
                    end
                end
                WADDR:if(m_awvalid&&m_awready)state<=WDATA;
                WDATA:if(m_wvalid&&m_wready)begin
                    physical_index_q<=physical_index_q+1'b1;
                    if(m_wlast)state<=WRESP;
                end
                WRESP:if(m_bvalid&&m_bready)begin
                    bresp_q<=m_bresp;
                    // state 按 (m_bid=={4'b0,id_q}) 选择候选来源；各分支结果仍属于当前寄存边界。
                    state<=(m_bid=={4'b0,id_q})?BOUT:FAULT;
                end
                BOUT:if(s_bvalid&&s_bready)state<=prefetch_valid?RWAIT_PENDING:IDLE;
                RADDR:if(m_arvalid&&m_arready)state<=RDATA;
                RDATA:if(m_rvalid)begin
                    physical_index_q<=physical_index_q+1'b1;
                    if(m_rid!={4'b0,id_q}||m_rlast!=(physical_index_q+1==physical_count_q))state<=FAULT;
                    else if(m_rlast)state<=ROUT;
                end
                ROUT,BADREAD:if(s_rvalid&&s_rready)begin
                    logical_index_q<=logical_index_q+1'b1;
                    if(s_rlast)state<=(state==ROUT&&prefetch_valid)?RWAIT_PENDING:IDLE;
                end
                RWAIT_PENDING:if(prefetch_state==PDONE)begin
                    id_q<=prefetch_id;logical_count_q<=prefetch_logical_count;
                    logical_index_q<=0;physical_index_q<=0;
                    physical_count_q<=prefetch_physical_count;
                    first_half_q<=prefetch_first_half;addr_q<=prefetch_addr;
                    active_bank<=~active_bank;
                    if(prefetch_write)begin
                        bresp_q<=prefetch_bresp;
                        state<=BOUT;
                    end else state<=prefetch_bad?BADREAD:ROUT;
                    prefetch_valid<=0;prefetch_state<=PNONE;
                end
                default:state<=FAULT;
            endcase
            // 本分支处理握手条件 s_arvalid 与 s_arready 与 s_awvalid 与 s_awready；仅满足当前条件时推进下述事务。
            if(offer_prefetch&&((s_arvalid&&s_arready)||(s_awvalid&&s_awready)))begin
                prefetch_valid<=1;prefetch_id<=s_arid;
                prefetch_write<=s_awvalid&&s_awready;
                prefetch_id<=(s_awvalid&&s_awready)?s_awid:s_arid;
                // prefetch_logical_count 按 (s_awvalid&&s_awready) 选择候选来源；各分支结果仍属于当前寄存边界。
                prefetch_logical_count<=(s_awvalid&&s_awready)?9'(s_awlen)+1:9'(s_arlen)+1;
                prefetch_logical_index<=0;
                prefetch_first_half<=(s_awvalid&&s_awready)?s_awaddr[4]:s_araddr[4];
                // prefetch_physical_count 按 (s_awvalid&&s_awready) 选择候选来源；各分支结果仍属于当前寄存边界。
                prefetch_physical_count<=(s_awvalid&&s_awready)?
                    4'((10'(s_awlen)+10'd2+10'(s_awaddr[4]))>>1):
                    4'((10'(s_arlen)+10'd2+10'(s_araddr[4]))>>1);
                prefetch_physical_index<=0;
                // prefetch_addr 按 (s_awvalid&&s_awready) 选择候选来源；各分支结果仍属于当前寄存边界。
                prefetch_addr<=(s_awvalid&&s_awready)?
                    30'((s_awaddr-DDR_BASE)&32'hffffffe0):
                    30'((s_araddr-DDR_BASE)&32'hffffffe0);
                prefetch_bad<=(s_awvalid&&s_awready)?
                    !legal(s_awaddr,s_awlen,s_awsize,s_awburst):
                    !legal(s_araddr,s_arlen,s_arsize,s_arburst);
                if(s_awvalid&&s_awready)begin
                    prefetch_bresp<=0;
                    prefetch_state<=PWC;
                end else prefetch_state<=legal(s_araddr,s_arlen,s_arsize,s_arburst)?PADDR:PDONE;
            end else case(prefetch_state)
                PADDR:if(m_arvalid&&m_arready)prefetch_state<=PDATA;
                PDATA:if(m_rvalid)begin
                    prefetch_physical_index<=prefetch_physical_index+1'b1;
                    if(m_rid!={4'b0,prefetch_id}||
                       m_rlast!=(prefetch_physical_index+1==prefetch_physical_count))
                        state<=FAULT;
                    else if(m_rlast)prefetch_state<=PDONE;
                end
                PWC:if(s_wvalid&&s_wready)begin
                    prefetch_logical_index<=prefetch_logical_index+1'b1;
                    if(s_wlast!=(prefetch_logical_index+1==prefetch_logical_count))state<=FAULT;
                    else if(s_wlast)begin
                        if(prefetch_bad)begin
                            prefetch_bresp<=2'b11;prefetch_state<=PDONE;
                        end else prefetch_state<=PWADDR;
                    end
                end
                PWADDR:if(m_awvalid&&m_awready)prefetch_state<=PWDATA;
                PWDATA:if(m_wvalid&&m_wready)begin
                    prefetch_physical_index<=prefetch_physical_index+1'b1;
                    if(m_wlast)prefetch_state<=PWRESP;
                end
                PWRESP:if(m_bvalid&&m_bready)begin
                    prefetch_bresp<=m_bresp;
                    if(m_bid!={4'b0,prefetch_id})state<=FAULT;
                    else prefetch_state<=PDONE;
                end
                default:begin end
            endcase
            // A missing completion or lost calibration needs a common reset;
            // never recycle an ID and let a late response complete new work.
            if((state!=IDLE&&!ddr_ready)||
               (wait_controller&&!controller_progress&&watchdog_q==WATCHDOG_W'(WATCHDOG_CYCLES-1))||
               (m_rvalid&&state!=RDATA&&prefetch_state!=PDATA))state<=FAULT;
        end
    end
    // The pending write lazily replaces only beat slots already consumed by
    // HMIC. First half-write to each reused slot rebuilds its full mask;
    // stale bytes in the other half are never strobed.
    for(genvar beat=0;beat<9;beat++)begin:GEN_WRITE_BEAT
        always_ff @(posedge clk)begin
            if(!rst)begin
                if(clear_active_mask)mask_q[beat]<=0;
                else if((write_fill_active||write_fill_prefetch)&&
                        write_fill_half[4:1]==beat[3:0])begin
                    wdata_q[beat][128*write_fill_half[0]+:128]<=s_wdata;
                    if(write_fill_prefetch&&
                       (prefetch_logical_index==0||!prefetch_half_index[0]))
                        mask_q[beat]<=write_fill_half[0]?
                            {s_wstrb,16'b0}:{16'b0,s_wstrb};
                    else mask_q[beat][16*write_fill_half[0]+:16]<=s_wstrb;
                end
            end
        end
    end
    // Read responses keep their existing independently reserved banks.
    for(genvar bank=0;bank<2;bank++)begin:GEN_BANK
        for(genvar beat=0;beat<9;beat++)begin:GEN_BEAT
            always_ff @(posedge clk)begin
                if(!rst)begin
                    if(m_rvalid&&(read_fill_active||read_fill_prefetch)&&
                       read_fill_bank==bank[0]&&read_fill_index==beat[3:0])begin
                        rdata_q[bank][beat]<=m_rdata;
                        resp_q[bank][beat]<=m_rresp;
                    end
                end
            end
        end
    end
endmodule
