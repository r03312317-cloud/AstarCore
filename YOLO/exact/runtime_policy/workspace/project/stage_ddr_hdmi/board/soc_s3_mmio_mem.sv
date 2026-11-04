// S3 Requant/LUT control at board MMIO 0x60001100..0x60001140.
// All ports are in the DDR UI clock domain; pg_mmio_cdc is upstream.
// Polling status is supported, including done, rejected and partial output.
module soc_s3_mmio_mem (
    input logic clk,rst,ddr_ready,axi_poisoned,
    input logic req_valid,output logic req_ready,
    input logic [15:0] req_addr,input logic req_write,
    input logic [31:0] req_wdata,input logic [3:0] req_wstrb,
    output logic rsp_valid,input logic rsp_ready,
    output logic [31:0] rsp_rdata,output logic rsp_error,
    output logic start_valid,input logic start_ready,
    input logic done_valid,output logic done_ready,
    input logic [3:0] engine_error,input logic engine_partial,
    input logic [31:0] engine_read_bytes,engine_write_bytes,
    input logic [31:0] engine_stall_cycles,engine_active_cycles,
    output logic [31:0] source_addr,output_addr,bias_addr,
    output logic [31:0] multiplier_addr,shift_addr,lut_addr,
    output logic use_lut,
    output logic [31:0] pixels,output logic [8:0] channels,
    output logic [31:0] acc_abs_bound,output logic [1:0] rounding_mode,
    output logic signed [31:0] output_zero,clamp_min,clamp_max
);
    logic busy,done_hold,rejected_hold,partial_hold;
    logic [3:0] error_hold;
    logic [31:0] config_q;
    wire hit=(req_addr>=16'h0100 && req_addr<=16'h0140 &&
              req_addr[1:0]==0);
    assign req_ready=!rst && !rsp_valid;
    assign done_ready=1'b1;
    assign rounding_mode=config_q[1:0];
    assign use_lut=config_q[2];
    assign output_zero={{24{config_q[15]}},config_q[15:8]};
    assign clamp_min={{24{config_q[23]}},config_q[23:16]};
    assign clamp_max={{24{config_q[31]}},config_q[31:24]};
    always_ff @(posedge clk) begin
        start_valid<=0;
        if(rst) begin
            rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;
            busy<=0;done_hold<=0;rejected_hold<=0;
            partial_hold<=0;error_hold<=0;
            source_addr<=0;output_addr<=0;bias_addr<=0;
            multiplier_addr<=0;shift_addr<=0;lut_addr<=0;
            pixels<=0;channels<=0;acc_abs_bound<=0;config_q<=0;
        end else begin
            if(done_valid) begin
                busy<=0;done_hold<=1;partial_hold<=engine_partial;
                error_hold<=engine_error;
            end
            if(rsp_valid && rsp_ready) rsp_valid<=0;
            if(req_valid && req_ready) begin
                rsp_valid<=1;rsp_error<=0;rsp_rdata<=0;
                if(!hit || (req_write && req_wstrb!=4'hf)) begin
                    rsp_error<=1;rejected_hold<=1;
                end else if(req_write) begin
                    if(busy && req_addr!=16'h012c) begin
                        rsp_error<=1;rejected_hold<=1;
                    end else case(req_addr)
                        16'h0100: if(req_wdata!=32'd1 || !start_ready ||
                                      !ddr_ready || axi_poisoned || busy) begin
                            rsp_error<=1;rejected_hold<=1;
                        end else begin
                            start_valid<=1;busy<=1;done_hold<=0;
                            rejected_hold<=0;partial_hold<=0;error_hold<=0;
                        end
                        16'h0104:source_addr<=req_wdata;
                        16'h0108:output_addr<=req_wdata;
                        16'h010c:bias_addr<=req_wdata;
                        16'h0110:multiplier_addr<=req_wdata;
                        16'h0114:shift_addr<=req_wdata;
                        16'h0118:lut_addr<=req_wdata;
                        16'h011c:pixels<=req_wdata;
                        16'h0120: if(req_wdata[31:9]!=0) begin
                            rsp_error<=1;rejected_hold<=1;
                        end else channels<=req_wdata[8:0];
                        16'h0124:acc_abs_bound<=req_wdata;
                        16'h0128:config_q<=req_wdata;
                        16'h012c: if(req_wdata==32'd1 && !busy) begin
                            done_hold<=0;rejected_hold<=0;
                            partial_hold<=0;error_hold<=0;
                        end else begin rsp_error<=1;rejected_hold<=1;end
                        default: begin rsp_error<=1;rejected_hold<=1;end
                    endcase
                end else case(req_addr)
                    16'h0100:rsp_rdata<=0;
                    16'h0104:rsp_rdata<=source_addr;
                    16'h0108:rsp_rdata<=output_addr;
                    16'h010c:rsp_rdata<=bias_addr;
                    16'h0110:rsp_rdata<=multiplier_addr;
                    16'h0114:rsp_rdata<=shift_addr;
                    16'h0118:rsp_rdata<=lut_addr;
                    16'h011c:rsp_rdata<=pixels;
                    16'h0120:rsp_rdata<={23'd0,channels};
                    16'h0124:rsp_rdata<=acc_abs_bound;
                    16'h0128:rsp_rdata<=config_q;
                    16'h012c:rsp_rdata<={20'd0,axi_poisoned,ddr_ready,
                        rejected_hold,partial_hold,error_hold,2'd0,done_hold,busy};
                    16'h0130:rsp_rdata<=engine_read_bytes;
                    16'h0134:rsp_rdata<=engine_write_bytes;
                    16'h0138:rsp_rdata<=engine_stall_cycles;
                    16'h013c:rsp_rdata<=engine_active_cycles;
                    16'h0140:rsp_rdata<=32'h3351_5253; // "SRQ3"
                    default:begin rsp_error<=1;rejected_hold<=1;end
                endcase
            end
        end
    end
endmodule
