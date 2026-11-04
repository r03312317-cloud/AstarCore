// RGB565 1280x720 -> 680x340, full-view centre-point nearest neighbour.
// sx=floor((32*x+16)/17), sy=floor((36*y+18)/17).  All transfers are
// 16-byte aligned; done is beat-level completion and the adapter fences B.
// 架构导读：soc_display_resize_core。
// 独立预览图像缩放核心，输出 HDMI 图像帧缓冲所需像素。
module soc_display_resize_core #(
    // 静态配置：parameter bit SKIP_UNSAMPLED = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit SKIP_UNSAMPLED = 1'b1,
    // 静态配置：parameter bit REFILL_SAME_CYCLE = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit REFILL_SAME_CYCLE = 1'b1
) (
    // 接口声明：input logic clk,rst,start。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic clk,rst,start,
    // 接口声明：input logic [29:0] src_base,dst_base。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input logic [29:0] src_base,dst_base,
    // 接口声明：output logic busy,done,rd_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic busy,done,rd_valid,
    // 接口声明：input logic rd_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic rd_ready,
    // 接口声明：output logic [29:0] rd_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [29:0] rd_addr,
    // 接口声明：input logic rsp_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input logic rsp_valid,
    // 接口声明：output logic rsp_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic rsp_ready,
    // 接口声明：input logic [127:0] rsp_data。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input logic [127:0] rsp_data,
    // 接口声明：output logic wr_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic wr_valid,
    // 接口声明：input logic wr_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic wr_ready,
    // 接口声明：output logic [29:0] wr_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [29:0] wr_addr,
    // 接口声明：output logic [127:0] wr_data。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    output logic [127:0] wr_data,
    // 接口声明：output logic [31:0] stat_rd_beats,stat_wr_beats。
    output logic [31:0] stat_rd_beats,stat_wr_beats
);
    timeunit 1ns; timeprecision 1ps;
    // 静态配置：localparam logic [31:0] READ_BEATS=32'd54400, WRITE_BEATS=32'd28900。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [31:0] READ_BEATS=32'd54400, WRITE_BEATS=32'd28900;
    logic [29:0] row_base_q,write_addr_q;
    logic [7:0] req_x_q;
    logic [4:0] y_rem_q,x_rem_q;
    logic [10:0] source_x_q,target_x_q;
    logic [31:0] issued_q;
    logic [2:0] inflight_q,beat_pixel_q,packed_count_q;
    logic beat_valid_q;
    logic [127:0] beat_q,packed_q;
    wire read_fire=rd_valid&&rd_ready;
    wire response_fire=rsp_valid&&rsp_ready;
    wire write_fire=wr_valid&&wr_ready;
    // Fast mode tracks the source beat, and visits only the exact selected
    // sample positions. It does not change any DDR read or sampling formula.
    wire selected=SKIP_UNSAMPLED ? (source_x_q[10:3]==target_x_q[10:3]) :
                                  (source_x_q==target_x_q);
    wire [10:0] target_next=target_x_q+(x_rem_q>=2 ? 11'd2:11'd1);
    wire [2:0] sample_lane=SKIP_UNSAMPLED ? target_x_q[2:0]:beat_pixel_q;
    wire beat_last=target_next[10:3]!=source_x_q[10:3];
    wire process_pixel=beat_valid_q&&(!selected||packed_count_q!=7||!wr_valid||wr_ready);
    assign rd_valid=busy&&issued_q<READ_BEATS&&inflight_q<3'd4;
    assign rd_addr=row_base_q+{18'd0,req_x_q,4'd0};
    assign rsp_ready=busy&&(!beat_valid_q ||
        (SKIP_UNSAMPLED&&REFILL_SAME_CYCLE&&process_pixel&&beat_last));
    // 过程边界：always_ff @(posedge clk or posedge rst) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk or posedge rst) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst)begin
            busy<=0;done<=0;row_base_q<=0;write_addr_q<=0;req_x_q<=0;
            y_rem_q<=0;x_rem_q<=0;source_x_q<=0;target_x_q<=0;
            issued_q<=0;inflight_q<=0;beat_pixel_q<=0;packed_count_q<=0;
            beat_valid_q<=0;beat_q<=0;packed_q<=0;
            wr_valid<=0;wr_addr<=0;wr_data<=0;stat_rd_beats<=0;stat_wr_beats<=0;
        end else begin
            done<=0;
            if(!busy&&start)begin
                busy<=1;row_base_q<=src_base+30'd2560;write_addr_q<=dst_base;
                req_x_q<=0;y_rem_q<=1;x_rem_q<=16;source_x_q<=0;target_x_q<=0;
                issued_q<=0;inflight_q<=0;beat_pixel_q<=0;packed_count_q<=0;
                beat_valid_q<=0;wr_valid<=0;stat_rd_beats<=0;stat_wr_beats<=0;
            end else if(busy)begin
                // 按 {read_fire,response_fire} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                case({read_fire,response_fire})
                    2'b10:inflight_q<=inflight_q+1'b1;
                    2'b01:inflight_q<=inflight_q-1'b1;
                    default:begin end
                endcase
                if(read_fire)begin
                    issued_q<=issued_q+1'b1;
                    if(req_x_q==159)begin
                        req_x_q<=0;
                        if(y_rem_q>=15)begin row_base_q<=row_base_q+30'd7680;y_rem_q<=y_rem_q-5'd15;end
                        else begin row_base_q<=row_base_q+30'd5120;y_rem_q<=y_rem_q+5'd2;end
                    end else req_x_q<=req_x_q+1'b1;
                end
                if(write_fire)begin
                    wr_valid<=0;stat_wr_beats<=stat_wr_beats+1'b1;
                    if(stat_wr_beats==WRITE_BEATS-1)begin busy<=0;done<=1;end
                end
                if(process_pixel)begin
                    if(selected)begin
                        if(packed_count_q==7)begin
                            wr_data<={beat_q[sample_lane*16+:16],packed_q[111:0]};
                            wr_addr<=write_addr_q;write_addr_q<=write_addr_q+30'd16;
                            wr_valid<=1;packed_count_q<=0;
                        end else begin
                            packed_q[packed_count_q*16+:16]<=beat_q[sample_lane*16+:16];
                            packed_count_q<=packed_count_q+1'b1;
                        end
                        if(x_rem_q>=2)begin target_x_q<=target_x_q+11'd2;x_rem_q<=x_rem_q-5'd2;end
                        else begin target_x_q<=target_x_q+11'd1;x_rem_q<=x_rem_q+5'd15;end
                    end
                    if(SKIP_UNSAMPLED)begin
                        if(beat_last)begin
                            beat_valid_q<=0;
                            if(source_x_q==1272)begin source_x_q<=0;target_x_q<=0;x_rem_q<=16;end
                            else source_x_q<=source_x_q+11'd8;
                        end
                    end else begin
                        if(source_x_q==1279)begin source_x_q<=0;target_x_q<=0;x_rem_q<=16;end
                        else source_x_q<=source_x_q+1'b1;
                        if(beat_pixel_q==7)begin beat_valid_q<=0;beat_pixel_q<=0;end
                        else beat_pixel_q<=beat_pixel_q+1'b1;
                    end
                end
                // A response may replace the consumed beat on this edge.
                // Replacement wins only after the old payload was sampled.
                if(response_fire)begin
                    beat_q<=rsp_data;beat_valid_q<=1;beat_pixel_q<=0;
                    stat_rd_beats<=stat_rd_beats+1'b1;
                end
            end
        end
    end
    // synthesis translate_off
    always_ff @(posedge clk)if(!rst&&busy&&SKIP_UNSAMPLED&&beat_valid_q)
        assert(selected) else $fatal(1,"RESIZE_SAMPLE_BEAT_IDENTITY");
    // synthesis translate_on
endmodule
