`timescale 1ns/1ps
// Exact board MMIO offset adaptation and dual-clock request/response path.
module tb_s3_cpu_cdc;
    logic cpu_clk=0,mem_clk=0,arst=1,mem_reset=1;
    always #3 cpu_clk=~cpu_clk;
    always #5 mem_clk=~mem_clk;
    logic cpu_req_valid=0,cpu_req_ready,cpu_req_write=0;
    logic [15:0] cpu_req_addr=0;
    logic [31:0] cpu_req_wdata=0;
    logic [3:0] cpu_req_wstrb=4'hf;
    logic cpu_rsp_valid,cpu_rsp_ready=1,cpu_rsp_error;
    logic [31:0] cpu_rsp_rdata;
    logic mem_req_valid,mem_req_ready,mem_req_write;
    logic [15:0] mem_req_addr;
    logic [31:0] mem_req_wdata;
    logic [3:0] mem_req_wstrb;
    logic mem_rsp_valid,mem_rsp_ready,mem_rsp_error;
    logic [31:0] mem_rsp_rdata;
    logic start_valid,start_ready=1,done_valid=0,done_ready;
    logic [3:0] engine_error=0;
    logic engine_partial=0;
    logic [31:0] engine_read_bytes=32'd944;
    logic [31:0] engine_write_bytes=32'd64;
    logic [31:0] engine_stall_cycles=32'd17;
    logic [31:0] engine_active_cycles=32'd91;
    logic [31:0] source_addr,output_addr,bias_addr;
    logic [31:0] multiplier_addr,shift_addr,lut_addr,pixels,acc_abs_bound;
    logic [8:0] channels;
    logic [1:0] rounding_mode;
    logic use_lut;
    logic signed [31:0] output_zero,clamp_min,clamp_max;
    logic [3:0] complete_delay=0;
    wire selected=(mem_req_addr[11:8]==4'h1);

    pg_mmio_cdc cdc(
        .src_clk(cpu_clk),.dst_clk(mem_clk),.arst,
        .s_req_valid(cpu_req_valid),.s_req_ready(cpu_req_ready),
        .s_req_addr(cpu_req_addr),.s_req_write(cpu_req_write),
        .s_req_wdata(cpu_req_wdata),.s_req_wstrb(cpu_req_wstrb),
        .s_rsp_valid(cpu_rsp_valid),.s_rsp_ready(cpu_rsp_ready),
        .s_rsp_rdata(cpu_rsp_rdata),.s_rsp_error(cpu_rsp_error),
        .m_req_valid(mem_req_valid),.m_req_ready(mem_req_ready),
        .m_req_addr(mem_req_addr),.m_req_write(mem_req_write),
        .m_req_wdata(mem_req_wdata),.m_req_wstrb(mem_req_wstrb),
        .m_rsp_valid(mem_rsp_valid),.m_rsp_ready(mem_rsp_ready),
        .m_rsp_rdata(mem_rsp_rdata),.m_rsp_error(mem_rsp_error));
    soc_s3_mmio_mem regs(
        .clk(mem_clk),.rst(mem_reset),.ddr_ready(1'b1),.axi_poisoned(1'b0),
        .req_valid(mem_req_valid && selected),.req_ready(mem_req_ready),
        .req_addr({4'b0000,mem_req_addr[11:0]}),
        .req_write(mem_req_write),.req_wdata(mem_req_wdata),
        .req_wstrb(mem_req_wstrb),
        .rsp_valid(mem_rsp_valid),.rsp_ready(mem_rsp_ready),
        .rsp_rdata(mem_rsp_rdata),.rsp_error(mem_rsp_error),
        .start_valid,.start_ready,.done_valid,.done_ready,.engine_error,
        .engine_partial,.engine_read_bytes,.engine_write_bytes,
        .engine_stall_cycles,.engine_active_cycles,.source_addr,.output_addr,
        .bias_addr,.multiplier_addr,.shift_addr,.lut_addr,.use_lut,
        .pixels,.channels,.acc_abs_bound,.rounding_mode,.output_zero,
        .clamp_min,.clamp_max);
    always_ff @(posedge mem_clk) begin
        if(mem_reset) begin complete_delay<=0;done_valid<=0;end
        else begin
            done_valid<=0;
            if(start_valid) complete_delay<=4;
            else if(complete_delay!=0) begin
                complete_delay<=complete_delay-1'b1;
                if(complete_delay==1) done_valid<=1;
            end
        end
    end

    task automatic access(input bit wr,input logic[15:0] address,
                          input logic[31:0] value,output logic[31:0] reply);
        @(negedge cpu_clk);
        cpu_req_addr=address;cpu_req_write=wr;cpu_req_wdata=value;
        cpu_req_valid=1;
        do @(posedge cpu_clk); while(!cpu_req_ready);
        @(negedge cpu_clk);cpu_req_valid=0;
        do @(posedge cpu_clk); while(!cpu_rsp_valid);
        if(cpu_rsp_error) $fatal(1,"CPU MMIO error address=%04x",address);
        reply=cpu_rsp_rdata;
    endtask
    task automatic write_reg(input logic[15:0] address,
                             input logic[31:0] value);
        logic[31:0] unused;
        access(1,address,value,unused);
    endtask
    task automatic read_reg(input logic[15:0] address,
                            output logic[31:0] value);
        access(0,address,0,value);
    endtask

    initial begin: run
        logic[31:0] value;
        int polls;
        repeat(5) @(negedge mem_clk);
        arst=0;mem_reset=0;
        read_reg(16'h1140,value);
        if(value!=32'h3351_5253) $fatal(1,"S3 identity not routed %08x",value);
        write_reg(16'h1104,32'h8000_1000);
        write_reg(16'h111c,32'd17);
        write_reg(16'h1120,32'd33);
        read_reg(16'h1104,value);
        if(value!=32'h8000_1000) $fatal(1,"CDC config readback %08x",value);
        write_reg(16'h1100,1);
        value=0;
        for(polls=0;polls<20 && !(value&32'h202);polls++)
            read_reg(16'h112c,value);
        if(value[9:4]!=0 || !value[10] || !value[1] || value[0])
            $fatal(1,"CPU completion status %08x",value);
        read_reg(16'h1130,value);
        if(value!=944) $fatal(1,"CPU engine counter %08x",value);
        $display("PASS tb_s3_cpu_cdc CPU MMIO 0x1100, CDC, completion, metrics");
        $finish;
    end
    initial begin
        repeat(10000) @(posedge cpu_clk);
        $fatal(1,"S3 CPU CDC timeout");
    end
endmodule
