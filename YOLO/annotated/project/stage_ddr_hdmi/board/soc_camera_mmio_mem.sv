// CPU-visible camera registers after the existing pg_mmio_cdc. All signals
// here use the HMIC user clock. A CPU write to CTRL bit0 arms one frame.
// Register map at 0x60001000: CTRL, BASE, STATUS, WRITTEN, SENSOR,
// ERRORS, DIMENSIONS, ID (word offsets 0,4,...,28).
// 架构导读：soc_camera_mmio_mem。
// 摄像头控制寄存器，向固件暴露 ready/busy/done、像素计数和错误。
module soc_camera_mmio_mem #(
    // 静态配置：parameter int WIDTH=1280, HEIGHT=720。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int WIDTH=1280, HEIGHT=720,
    // 静态配置：parameter bit CAPTURE_CHANNEL=0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit CAPTURE_CHANNEL=0,
    // 静态配置：parameter bit IMAGE_ACCEL_PRESENT=0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit IMAGE_ACCEL_PRESENT=0
)(
    // 接口声明：input logic clk,rst,ddr_ready,camera_init_done。
    // 表达本地完成/结束条件，系统退休还需满足上层接口契约。
    input logic clk,rst,ddr_ready,camera_init_done,
    // 接口声明：input logic req_valid,output logic req_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic req_valid,output logic req_ready,
    // 接口声明：input logic [15:0] req_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input logic [15:0] req_addr,
    // 接口声明：input logic req_write,input logic [31:0] req_wdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input logic req_write,input logic [31:0] req_wdata,
    // 接口声明：input logic [3:0] req_wstrb。
    // 按字节选择本次写入生效的 lane。
    input logic [3:0] req_wstrb,
    // 接口声明：output logic rsp_valid,input logic rsp_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic rsp_valid,input logic rsp_ready,
    // 接口声明：output logic [31:0] rsp_rdata,output logic rsp_error。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic [31:0] rsp_rdata,output logic rsp_error,
    // 接口声明：output logic start。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic start,
    // 接口声明：output logic [31:0] frame_base。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [31:0] frame_base,
    // 接口声明：input logic camera_ready,camera_busy,camera_done,camera_valid。
    input logic camera_ready,camera_busy,camera_done,camera_valid,
    input logic [7:0] camera_errors,
    input logic [31:0] pixels_written,sensor_pixels,
    input logic [511:0] diag_words,
    output logic diag_snapshot,
    input logic camera_init_done_1,
    input logic [511:0] diag_words_1,
    output logic diag_snapshot_1,
    output logic [5:0] sccb_control,
    input logic [31:0] camera_io_levels
);
    timeunit 1ns;timeprecision 1ps;
    logic done_hold;
    logic [31:0] status_word;
    wire capture_initialized=CAPTURE_CHANNEL?camera_init_done_1:camera_init_done;
    wire capture_manual=CAPTURE_CHANNEL?sccb_control[1]:sccb_control[0];
    assign req_ready=!rst&&!rsp_valid;
    assign status_word={25'b0,capture_initialized,(|camera_errors),ddr_ready,camera_valid,
                        done_hold,camera_busy,camera_ready};
    // 过程边界：always_ff @(posedge clk)begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk)begin
        start<=0;diag_snapshot<=0;diag_snapshot_1<=0;
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst)begin
            rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;
            frame_base<=32'h8001_0000;done_hold<=0;sccb_control<=0;
        end else begin
            if(camera_done)done_hold<=1;
            // 握手/背压判断：rsp_valid&&rsp_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if(rsp_valid&&rsp_ready)rsp_valid<=0;
            // 握手/背压判断：req_valid&&req_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if(req_valid&&req_ready)begin
                rsp_valid<=1;rsp_error<=0;rsp_rdata<=0;
                if(req_addr[1:0]!=0 || req_addr[11:8]!=0)rsp_error<=1;
                else if(req_write)begin
                    // 按 req_addr[7:2] 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                    case(req_addr[7:2])
                        5'd0: if(req_wstrb!=4'hf || req_wdata[31:1]!=0)
                            rsp_error<=1;
                        else if(req_wdata[0])begin
                            if(camera_ready&&ddr_ready&&capture_initialized&&!capture_manual)begin
                                start<=1;done_hold<=0;
                            end else rsp_error<=1;
                        end
                        5'd1: if(req_wstrb==4'hf && camera_ready)
                            frame_base<=req_wdata;
                        else rsp_error<=1;
                        5'd8: if(req_wstrb==4'hf && req_wdata==1)
                            diag_snapshot<=1;
                        else rsp_error<=1;
                        6'd24: if(req_wstrb==4'hf && req_wdata[31:6]==0 &&
                            !camera_busy && camera_ready && camera_init_done && camera_init_done_1)
                            sccb_control<=req_wdata[5:0];
                        else rsp_error<=1;
                        6'd32: if(req_wstrb==4'hf && req_wdata==1)
                            diag_snapshot_1<=1;
                        else rsp_error<=1;
                        default:rsp_error<=1;
                    endcase
                end else begin
                    // 按 req_addr[7:2] 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                    case(req_addr[7:2])
                        5'd0:rsp_rdata<=0;
                        5'd1:rsp_rdata<=frame_base;
                        5'd2:rsp_rdata<=status_word;
                        5'd3:rsp_rdata<=pixels_written;
                        5'd4:rsp_rdata<=sensor_pixels;
                        5'd5:rsp_rdata<={24'b0,camera_errors};
                        5'd6:rsp_rdata<={16'(HEIGHT),16'(WIDTH)};
                        5'd7:rsp_rdata<=32'h4341_4d31; // "CAM1"
                        6'd24:rsp_rdata<={IMAGE_ACCEL_PRESENT,25'b0,sccb_control};
                        6'd25:rsp_rdata<={29'b0,camera_busy,camera_init_done_1,camera_init_done};
                        6'd26:rsp_rdata<=camera_io_levels;
                        6'd27:rsp_rdata<=32'h31424353; // "SCB1"
                        6'd28:rsp_rdata<=32'(CAPTURE_CHANNEL);
                        default:if(req_addr[7:2]>=8 && req_addr[7:2]<=23)
                            rsp_rdata<=diag_words[32*(req_addr[7:2]-8)+:32];
                        else if(req_addr[7:2]>=32 && req_addr[7:2]<=47)
                            rsp_rdata<=diag_words_1[32*(req_addr[7:2]-32)+:32];
                        else rsp_error<=1;
                    endcase
                end
            end
        end
    end
endmodule
