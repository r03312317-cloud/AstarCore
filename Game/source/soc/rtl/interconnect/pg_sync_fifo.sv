// [ARCH] 同一时钟内解耦生产与消费，各自握手决定是否成功入队或出队。
// [ARCH] 空满依据占用状态，不能通过数据内容判断。
// [ARCH] 同拍读写按净变化更新数量，不能互相覆盖。
// [ARCH] 复位清除有效数量，不要求将全部数据阵列清零。
// Registered-occupancy FIFO; no out_ready -> in_ready combinational path.
module pg_sync_fifo #(
    parameter int WIDTH=32, DEPTH=16
)(
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input logic clk,rst,
    // [ARCH] in_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 push 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic in_valid, output logic in_ready, input logic [WIDTH-1:0] in_data,
    // [ARCH] out_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 out_data, pop 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic out_valid, input logic out_ready, output logic [WIDTH-1:0] out_data,
    output logic [$clog2(DEPTH+1)-1:0] level
);
    localparam int CW=$clog2(DEPTH+1);
    localparam int PW=(DEPTH<2)?1:$clog2(DEPTH);
    logic [PW-1:0] rp,wp;
    // [ARCH] data：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 out_data, wp 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [WIDTH-1:0] data[DEPTH];
    // [ARCH] push：控制一次状态/载荷接纳，调试时与对应有效身份和资源条件一起观察。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 data, wp 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic push,pop;
    assign in_ready=!rst&&(level<CW'(DEPTH));
    assign out_valid=!rst&&(level!=0);
    assign out_data=out_valid?data[rp]:'0;
    assign push=in_valid&&in_ready;
    assign pop=out_valid&&out_ready;
    function automatic logic [PW-1:0] inc(input logic [PW-1:0] p);
        return (p==PW'(DEPTH-1))?'0:p+1'b1;
    endfunction
    initial if(WIDTH<1||DEPTH<1) $fatal(1,"PG_FIFO_PARAMETER_RED");
    always_ff @(posedge clk) begin
        if(rst) begin rp<='0;wp<='0;level<='0;end
        else begin
            case({push,pop})
                2'b10:level<=level+1'b1;
                2'b01:level<=level-1'b1;
                default:begin end
            endcase
            if(push)begin data[wp]<=in_data;wp<=inc(wp);end
            if(pop)rp<=inc(rp);
        end
    end
endmodule
