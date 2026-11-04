// SPDX-License-Identifier: MIT
// Serialize the Linux SoC's 64-byte cache-line channels into 16-byte native
// transactions. Exactly one native request is outstanding. CPU-side read
// beats may be stalled independently; write completion is emitted only after
// all four native writes have received their real responses.
// 此桥将 CPU 的 64 位行拍接口转换为 DDR 侧 128 位带标签事务。
// 读响应拆分与写拍拼接都必须保存原请求所有者，不能仅凭返回先后猜测用途。
// 请求接受 写数据完成 与最终写响应是不同阶段，写完成不能提前报告给 cache。
// 字节 strobe 控制真正修改的字节，128 位数据总线宽度不表示每次都写满整拍。
// 错误一旦影响当前事务会沿响应路径传播，不能让原请求永久等待。
module rv32_line_to_native128 #(
    parameter [31:0] RAM_BASE = 32'h8000_0000,
    parameter [31:0] RAM_LIMIT = 32'h8400_0000
)(
    // enable 保存功能或输出使能，控制资格而非实际吞吐测量值。
    input wire clk, reset, enable,
    // instr_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
    input wire instr_req, input wire [31:0] instr_addr, input wire instr_io,
    output wire instr_gnt, output wire instr_rvalid, input wire instr_rready,
    // instr_rdata 保存读响应 payload，须在响应有效时才能使用。
    output wire [63:0] instr_rdata, output wire instr_err,
    // data_rd_addr 属于D-cache 状态，保存地址字段，随同所属请求传递，不能从后续新请求重取。
    // 脏行替换必须先保留待写回数据，不能被新回填覆盖。
    input wire data_rd_req, input wire data_rd_id, input wire [31:0] data_rd_addr,
    output wire data_rd_gnt, output wire data_rd_rvalid, input wire data_rd_rready,
    // data_rd_rdata 属于D-cache 状态，保存读响应 payload，须在响应有效时才能使用。
    output wire data_rd_rid, output wire [63:0] data_rd_rdata, output wire data_rd_err,
    input wire data_wr_req, input wire data_wr_last, input wire data_wr_id,
    // data_wr_addr 属于D-cache 状态，保存地址字段，随同所属请求传递，不能从后续新请求重取。
    input wire [31:0] data_wr_addr, input wire [63:0] data_wr_data,
    output wire data_wr_gnt, output wire data_wr_bvalid,
    output wire data_wr_bid, output wire data_wr_berr,
    // mem_req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output wire mem_req_valid, input wire mem_req_ready, output wire mem_req_write,
    // mem_req_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
    output wire [31:0] mem_req_addr, output wire [127:0] mem_req_wdata,
    // mem_req_wstrb 保存逐字节写使能，未使能的字节保持原值。
    output wire [15:0] mem_req_wstrb, output wire [3:0] mem_req_tag,
    // mem_rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    input wire mem_rsp_valid, output wire mem_rsp_ready, input wire mem_rsp_write,
    // mem_rsp_rdata 保存读响应 payload，须在响应有效时才能使用。
    input wire [127:0] mem_rsp_rdata, input wire [3:0] mem_rsp_tag,
    // mem_rsp_error 保存访问或译码错误标志，不能被正常数据值掩盖。
    input wire mem_rsp_error, output reg protocol_fault
);
    localparam [2:0] IDLE=0, WRITE_COLLECT=1, NATIVE_REQUEST=2,
                     NATIVE_WAIT=3, READ_BEATS=4, WRITE_REPLY=5;
    localparam [1:0] INSTR=0, DATA_READ=1, DATA_WRITE=2, NONE=3;
    // state 保存协议或执行状态，决定本周期允许的阶段与握手动作。
    reg [2:0] state;
    reg [1:0] owner, next_preference, chunk;
    // collect_index 保存表或队列的索引，须配合有效位与对应所有者使用。
    reg [2:0] collect_index;
    // line_address 保存地址 payload，具体是虚拟或物理地址由所在接口边界决定。
    reg [31:0] line_address;
    reg line_id, half, line_error, pair_error;
    reg [127:0] pair_data;
    reg [63:0] write_words [0:7];
    reg [1:0] choice;
    // taking_read 的资格组合为 state==IDLE && enable && (choice==INSTR || choice==DATA_READ)。
    // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
    wire taking_read = state==IDLE && enable && (choice==INSTR || choice==DATA_READ);
    // taking_write 的资格组合为 state==IDLE && enable && choice==DATA_WRITE。
    wire taking_write = state==IDLE && enable && choice==DATA_WRITE;
    // native_fire 的资格组合为 mem_req_valid && mem_req_ready。
    wire native_fire = mem_req_valid && mem_req_ready;
    // response_fire 的资格组合为 mem_rsp_valid && mem_rsp_ready。
    wire response_fire = mem_rsp_valid && mem_rsp_ready;
    // expected_tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    // expected_tag 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {owner,chunk}；复制大括号表示重复位域，不是独立队列元素。
    wire [3:0] expected_tag = {owner,chunk};
    // bad_response 的资格组合为 mem_rsp_error || mem_rsp_tag!=expected_tag || mem_rsp_write!=(owner==DATA_WRITE)。
    wire bad_response = mem_rsp_error || mem_rsp_tag!=expected_tag ||
                        mem_rsp_write!=(owner==DATA_WRITE);
    // requested_address 保存地址 payload，具体是虚拟或物理地址由所在接口边界决定。
    // requested_address 按 choice==INSTR 进行来源选择。
    // 真分支取 instr_addr；其余情况取 choice==DATA_READ ? data_rd_addr : data_wr_addr。
    wire [31:0] requested_address = choice==INSTR ? instr_addr :
                                    // choice 按 =DATA_READ 进行来源选择。
                                    // 真分支取 data_rd_addr；其余情况取 data_wr_addr。
                                    choice==DATA_READ ? data_rd_addr : data_wr_addr;
    // invalid_line 的资格组合为 requested_address[5:0]!=0 || requested_address<RAM_BASE || requested_address>RAM_LIMIT-32'd64 || (choice==INSTR && instr_io)。
    wire invalid_line = requested_address[5:0]!=0 || requested_address<RAM_BASE ||
                        requested_address>RAM_LIMIT-32'd64 ||
                        (choice==INSTR && instr_io);

    always @* begin
        // choice 连接到 NONE，两者在此路径上保持字段对应。
        choice=NONE;
        case(next_preference)
          INSTR: if(instr_req) choice=INSTR; else if(data_rd_req) choice=DATA_READ;
                 else if(data_wr_req) choice=DATA_WRITE;
          DATA_READ: if(data_rd_req) choice=DATA_READ; else if(data_wr_req) choice=DATA_WRITE;
                     else if(instr_req) choice=INSTR;
          default: if(data_wr_req) choice=DATA_WRITE; else if(instr_req) choice=INSTR;
                   else if(data_rd_req) choice=DATA_READ;
        endcase
    end

    // instr_gnt 的资格组合为 taking_read && choice==INSTR。
    assign instr_gnt = taking_read && choice==INSTR;
    // data_rd_gnt 的资格组合为 taking_read && choice==DATA_READ。
    assign data_rd_gnt = taking_read && choice==DATA_READ;
    // data_wr_gnt 的资格组合为 taking_write || (state==WRITE_COLLECT && enable)。
    assign data_wr_gnt = taking_write || (state==WRITE_COLLECT && enable);
    // instr_rvalid 的资格组合为 state==READ_BEATS && owner==INSTR。
    assign instr_rvalid = state==READ_BEATS && owner==INSTR;
    // data_rd_rvalid 的资格组合为 state==READ_BEATS && owner==DATA_READ。
    assign data_rd_rvalid = state==READ_BEATS && owner==DATA_READ;
    // instr_rdata 按 half 选择候选来源；各分支结果仍属于当前组合路径。
    // instr_rdata 按 half 进行来源选择。
    // 真分支取 pair_data[127:64]；其余情况取 pair_data[63:0]。
    assign instr_rdata = half ? pair_data[127:64] : pair_data[63:0];
    // data_rd_rdata 连接到 instr_rdata，两者在此路径上保持字段对应。
    assign data_rd_rdata = instr_rdata;
    // instr_err 连接到 pair_error，两者在此路径上保持字段对应。
    assign instr_err = pair_error;
    // data_rd_err 连接到 pair_error，两者在此路径上保持字段对应。
    assign data_rd_err = pair_error;
    // data_rd_rid 连接到 line_id，两者在此路径上保持字段对应。
    assign data_rd_rid = line_id;
    // data_wr_bvalid 由比较式 state==WRITE_REPLY 产生；该结果是条件判断，不是被比较的数据。
    assign data_wr_bvalid = state==WRITE_REPLY;
    // data_wr_bid 连接到 line_id，两者在此路径上保持字段对应。
    assign data_wr_bid = line_id;
    // data_wr_berr 连接到 line_error，两者在此路径上保持字段对应。
    assign data_wr_berr = line_error;
    // mem_req_valid 的资格组合为 state==NATIVE_REQUEST && enable。
    assign mem_req_valid = state==NATIVE_REQUEST && enable;
    // mem_req_write 由比较式 owner==DATA_WRITE 产生；该结果是条件判断，不是被比较的数据。
    assign mem_req_write = owner==DATA_WRITE;
    // mem_req_addr 按 line_address + {26'd0,chunk,4'b0} 计算，运算位宽与有无符号以原声明和显式扩展为准。
    assign mem_req_addr = line_address + {26'd0,chunk,4'b0};
    // mem_req_wdata 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {write_words[{chunk,1'b1}],write_words[{chunk,1'b0}]}；复制大括号表示重复位域，不是独立队列元素。
    assign mem_req_wdata = {write_words[{chunk,1'b1}],write_words[{chunk,1'b0}]};
    // mem_req_wstrb 按 owner==DATA_WRITE 选择候选来源；各分支结果仍属于当前组合路径。
    // mem_req_wstrb 按 owner==DATA_WRITE 进行来源选择。
    // 真分支取 16'hffff；其余情况取 16'h0000。
    assign mem_req_wstrb = owner==DATA_WRITE ? 16'hffff : 16'h0000;
    // mem_req_tag 连接到 expected_tag，两者在此路径上保持字段对应。
    assign mem_req_tag = expected_tag;
    // mem_rsp_ready 由比较式 state==NATIVE_WAIT 产生；该结果是条件判断，不是被比较的数据。
    assign mem_rsp_ready = state==NATIVE_WAIT;

    always @(posedge clk) begin
        // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
        if(reset) begin
            // state 在此时钟更新路径捕获 IDLE，该更新仍受外层条件与后续同块赋值优先级限定。
            state<=IDLE; owner<=NONE; next_preference<=INSTR; chunk<=0;
            collect_index<=0; line_address<=0; line_id<=0; half<=0;
            line_error<=0; pair_error<=0; pair_data<=0; protocol_fault<=0;
        end else begin
            case(state)
              IDLE: begin
                  if(taking_read || taking_write) begin
                      owner<=choice;
                      next_preference<=choice==DATA_WRITE ? INSTR : choice+1'b1;
                      line_address<=requested_address;
                      line_id<=choice==DATA_READ ? data_rd_id : data_wr_id;
                      line_error<=invalid_line;
                      chunk<=0; half<=0;
                      if(taking_write) begin
                          write_words[0]<=data_wr_data;
                          collect_index<=1;
                          if(data_wr_last || invalid_line) begin
                              line_error<=1; protocol_fault<=1;
                          end
                          state<=WRITE_COLLECT;
                      end else if(invalid_line) begin
                          pair_data<=0; pair_error<=1; state<=READ_BEATS;
                          protocol_fault<=1;
                      end else state<=NATIVE_REQUEST;
                  end
              end
              WRITE_COLLECT: if(data_wr_req && data_wr_gnt) begin
                  write_words[collect_index]<=data_wr_data;
                  if(data_wr_addr!=line_address || data_wr_id!=line_id ||
                     data_wr_last!=(collect_index==7)) begin
                      line_error<=1; protocol_fault<=1;
                  end
                  if(collect_index==7) begin
                      chunk<=0;
                      if(line_error || data_wr_addr!=line_address || data_wr_id!=line_id || !data_wr_last)
                          state<=WRITE_REPLY;
                      else state<=NATIVE_REQUEST;
                  end else collect_index<=collect_index+1'b1;
              end
              NATIVE_REQUEST: if(native_fire) state<=NATIVE_WAIT;
              NATIVE_WAIT: if(response_fire) begin
                  if(bad_response) begin
                      line_error<=1;
                      if(mem_rsp_tag!=expected_tag || mem_rsp_write!=(owner==DATA_WRITE))
                          protocol_fault<=1;
                  end
                  if(owner==DATA_WRITE) begin
                      if(chunk==3) state<=WRITE_REPLY;
                      else begin chunk<=chunk+1'b1; state<=NATIVE_REQUEST; end
                  end else begin
                      pair_data<=mem_rsp_rdata;
                      pair_error<=bad_response;
                      half<=0; state<=READ_BEATS;
                  end
              end
              READ_BEATS: if((owner==INSTR && instr_rready) ||
                             (owner==DATA_READ && data_rd_rready)) begin
                  if(!half) half<=1;
                  else if(chunk==3) state<=IDLE;
                  else begin
                      chunk<=chunk+1'b1; half<=0;
                      if(line_error) begin pair_data<=0; pair_error<=1; end
                      else state<=NATIVE_REQUEST;
                  end
              end
              WRITE_REPLY: state<=IDLE;
              default: begin state<=IDLE; protocol_fault<=1; end
            endcase
        end
    end
endmodule
