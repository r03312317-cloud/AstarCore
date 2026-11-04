// Original Soc-Core RAM misalignment adapter, November 2026.
// Aligned transfers are combinational pass-throughs. Misaligned half/word
// payloads are unshifted at u_wdata; results are normalized at u_rdata.
// Split stores are non-atomic. A bounded map failure is rejected before any
// subrequest; a later bus error can leave an earlier partial store visible.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 将 RAM 中非对齐半字或字访问拆成对齐的 32 位子事务。
// 对齐访问组合直通，不为所有访存无条件增加流水级。
// 非对齐请求保存地址偏移、写数据与字节掩码，逐次发送首字及必要时的次字。
// 跨字读结果拼接并右移，使上游获得规范化数据；Store 按字节掩码分别更新。
// MMIO 或超过允许 RAM 范围的拆分在发出子请求前拒绝。
// 若后一个子请求出现总线错误，之前的部分 Store 可能已可见，拆分 Store
// 不保证原子性。
// 子请求与最终响应在背压时必须稳定，VERILATOR 断言检查这些保持条件。
// reset 同步清除适配状态，本模块不自行重放已经确认的副作用。
// 接口契约与阅读示例
// 例子  位于地址低两位为3的32位读需要访问对齐字A和A+4。
// 首字返回暂存，次字返回后拼成64位右移24位，得到所需低32位。
// 半字访问只有低两位为3时跨字，偏移1的半字只需一个对齐子字。
// 拆分请求保存原Store数据及8位字节掩码，再分成两个32位请求的4位掩码。
// 先检查last_address的33位结果，拒绝跨越4GiB回绕的访问。
// 完整范围检查在首子事务前进行，避免明显越界Store先写一半才发现越界。
// 总线自身在第二子事务返回错误时仍可能造成部分写入，
// 这与预先可判断的范围失败不同。
// 适配器允许请求当拍得到响应，first_transfer/second_transfer同时覆盖这一情况。
// 最终响应进入RESPONSE后保持到u_rready，不能让次字新数据改变已拥有结果。
module rv32_unaligned_adapter #(
    // 参数 ENABLE_DATA_RAM_GUARD：启用板级RAM边界知识，防止越界行访问；
    // 不是MMU或页级权限机制。
    parameter ENABLE_DATA_RAM_GUARD=0,
    // 参数 DATA_RAM_BASE：本板可访问RAM的包含式低边界，0x10000000。
    parameter [31:0] DATA_RAM_BASE=32'h00000000,
    // 参数 DATA_RAM_LIMIT：本板可访问RAM的包含式高边界，0x1000ffff。
    parameter [31:0] DATA_RAM_LIMIT=32'hffffffff
)(
    // 接口字段：input clk,reset。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
    input clk,reset,
    // 接口字段：input u_valid,output u_ready,input [31:0] u_address,input
    // u_write。
    // 事务握手。valid与对应ready同边界才接收；背压期间有主状态的载荷必须保持。
    input u_valid,output u_ready,input [31:0] u_address,input u_write,
    // 接口字段：input [31:0] u_wdata,input [3:0] u_wstrb,input [1:0] u_size。
    // 访存载荷或字节控制。地址、大小与字节掩码必须属于同一笔已接受事务。
    input [31:0] u_wdata,input [3:0] u_wstrb,input [1:0] u_size,
    // 接口字段：output u_rvalid,input u_rready,output [31:0] u_rdata,output
    // u_error。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    output u_rvalid,input u_rready,output [31:0] u_rdata,output u_error,
    // 接口字段：output m_valid,input m_ready,output [31:0] m_address,output
    // m_write。
    // 事务握手。valid与对应ready同边界才接收；背压期间有主状态的载荷必须保持。
    output m_valid,input m_ready,output [31:0] m_address,output m_write,
    // 接口字段：output [31:0] m_wdata,output [3:0] m_wstrb,output [1:0]
    // m_size。
    // 访存载荷或字节控制。地址、大小与字节掩码必须属于同一笔已接受事务。
    output [31:0] m_wdata,output [3:0] m_wstrb,output [1:0] m_size,
    // 接口字段：input m_rvalid,output m_rready,input [31:0] m_rdata,input
    // m_error。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    input m_rvalid,output m_rready,input [31:0] m_rdata,input m_error
);
    localparam [2:0] IDLE=0,REQUEST0=1,WAIT0=2,REQUEST1=3,WAIT1=4,RESPONSE=5;
    reg [2:0] state;
    reg [31:0] address,first_data,result_data;
    reg [63:0] store_data;
    reg [7:0] store_mask;
    reg write_operation,second_needed,result_error;
    reg [1:0] byte_offset;
    wire misaligned=(u_size==2&&u_address[1:0]!=0)||(u_size==1&&u_address[0]);
    wire [32:0] last_address={1'b0,u_address}+(u_size==1?33'd1:33'd3);
    // 函数 peripheral：判断外设区间；处于该范围的访问必须保留外设副作用语义，
    // 不能按普通 Cache 行拆分。
    // 调用字段：input [31:0] a。
    // 返回值是局部组合计算；调用者继续负责有效性、标签或表项命中条件。
    function peripheral;
        input [31:0] a;
        begin peripheral=a>=32'h30000000&&a<32'h84000000;end
    endfunction
    wire split_allowed=!last_address[32]&&!peripheral(u_address)&&!peripheral(last_address[31:0])&&
        (!ENABLE_DATA_RAM_GUARD||(u_address>=DATA_RAM_BASE&&last_address[31:0]<=DATA_RAM_LIMIT));
    wire idle=state==IDLE;
    wire first_request=state==REQUEST0;
    wire second_request=state==REQUEST1;
    wire first_transfer=m_rvalid&&(state==WAIT0||(first_request&&m_ready));
    wire second_transfer=m_rvalid&&(state==WAIT1||(second_request&&m_ready));
    wire [63:0] combined={m_rdata,first_data}>>{byte_offset,3'b0};
    assign u_ready=!reset&&idle&&m_ready;
    assign m_valid=!reset&&(idle?(u_valid&&!misaligned):(first_request||second_request));
    assign m_address=idle?u_address:(address+(second_request?32'd4:32'd0));
    assign m_write=idle?u_write:write_operation;
    assign m_wdata=idle?u_wdata:(second_request?store_data[63:32]:store_data[31:0]);
    assign m_wstrb=idle?u_wstrb:(second_request?store_mask[7:4]:store_mask[3:0]);
    assign m_size=idle?u_size:2'd2;
    assign u_rvalid=!reset&&(idle?m_rvalid:state==RESPONSE);
    assign u_rdata=idle?m_rdata:result_data;
    assign u_error=idle?m_error:result_error;
    assign m_rready=!reset&&(idle?u_rready:(first_request||state==WAIT0||second_request||state==WAIT1));
    always @(posedge clk)begin
        if(reset)begin
            state<=IDLE;address<=0;first_data<=0;result_data<=0;
            store_data<=0;store_mask<=0;write_operation<=0;
            second_needed<=0;result_error<=0;byte_offset<=0;
        end else begin
            case(state)
            IDLE:if(u_valid&&u_ready&&misaligned)begin
                address<={u_address[31:2],2'b0};byte_offset<=u_address[1:0];
                write_operation<=u_write;
                store_data<={32'b0,u_wdata}<<{u_address[1:0],3'b0};
                store_mask<={4'b0,u_wstrb}<<u_address[1:0];
                second_needed<=u_size==2||u_address[1:0]==3;
                result_error<=!split_allowed;result_data<=0;
                state<=split_allowed?REQUEST0:RESPONSE;
            end
            REQUEST0,WAIT0:begin
                if(first_request&&m_ready)state<=WAIT0;
                if(first_transfer)begin
                    first_data<=m_rdata;result_error<=m_error;
                    if(second_needed&&!m_error)state<=REQUEST1;
                    else begin result_data<=m_rdata>>{byte_offset,3'b0};state<=RESPONSE;end
                end
            end
            REQUEST1,WAIT1:begin
                if(second_request&&m_ready)state<=WAIT1;
                if(second_transfer)begin
                    result_data<=combined[31:0];result_error<=m_error;state<=RESPONSE;
                end
            end
            RESPONSE:if(u_rready)state<=IDLE;
            default:state<=IDLE;
            endcase
        end
    end
`ifdef VERILATOR
    reg held_request,held_response;
    reg [70:0] prior_request;
    reg [32:0] prior_response;
    always @(posedge clk)begin
        if(reset)begin held_request<=0;held_response<=0;end
        else begin
            if(held_request&&(!m_valid||{m_address,m_write,m_wdata,m_wstrb,m_size}!=prior_request))
                $fatal(1,"Unaligned adapter changed a held cache request");
            if(held_response&&(!u_rvalid||{u_error,u_rdata}!=prior_response))
                $fatal(1,"Unaligned adapter changed a held CPU response");
            held_request<=m_valid&&!m_ready;
            prior_request<={m_address,m_write,m_wdata,m_wstrb,m_size};
            held_response<=u_rvalid&&!u_rready;prior_response<={u_error,u_rdata};
        end
    end
`endif
endmodule
