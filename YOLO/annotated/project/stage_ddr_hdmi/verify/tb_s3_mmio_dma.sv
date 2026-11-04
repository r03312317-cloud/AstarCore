`timescale 1ns/1ps
// CPU-style MMIO -> S3 engine -> DDR beat model. AXI translation is tested
// separately by tb_s3_axi; physical-board tests cover the assembled path.
module tb_s3_mmio_dma;
    localparam logic [31:0] BASE=32'h8000_0000;
    logic clk=0;
    always #5 clk=~clk;
    logic rst=1,ddr_ready=1,axi_poisoned=0;
    logic req_valid=0,req_ready,req_write=0,rsp_valid,rsp_ready=1,rsp_error;
    logic [15:0] req_addr=0;
    logic [31:0] req_wdata=0,rsp_rdata;
    logic [3:0] req_wstrb=4'hf;
    logic start_valid,start_ready,done_valid,done_ready;
    logic [3:0] engine_error;
    logic engine_partial,use_lut;
    logic [31:0] engine_read_bytes,engine_write_bytes;
    logic [31:0] engine_stall_cycles,engine_active_cycles;
    logic [31:0] source_addr,output_addr,bias_addr;
    logic [31:0] multiplier_addr,shift_addr,lut_addr;
    logic [31:0] pixels,acc_abs_bound;
    logic [8:0] channels;
    logic [1:0] rounding_mode;
    logic signed [31:0] output_zero,clamp_min,clamp_max;
    logic dma_req_valid,dma_req_ready,dma_req_write;
    logic [31:0] dma_req_addr;
    logic [127:0] dma_req_wdata,dma_rsp_rdata;
    logic [15:0] dma_req_wstrb;
    logic [3:0] dma_req_id,dma_rsp_id;
    logic dma_rsp_valid,dma_rsp_ready,dma_rsp_write,dma_rsp_error;
    logic [7:0] memory[0:65535];
    logic [7:0] expected[0:4095];
    logic pending=0,pending_write=0,ready_gate=0;
    logic [2:0] delay_count=0;
    logic [127:0] response_data=0;
    int reads=0,writes=0;

    soc_s3_mmio_mem regs(.*);
    soc_requant_lut_dma #(.DDR_BASE(BASE)) engine(
        .clk,.rst,.start_valid,.start_ready,.source_addr,.output_addr,
        .bias_addr,.multiplier_addr,.shift_addr,.lut_addr,.use_lut,
        .pixels,.channels,.acc_abs_bound,.rounding_mode,.output_zero,
        .clamp_min,.clamp_max,.done_valid,.done_ready,
        .error_code(engine_error),.partial_output(engine_partial),
        .read_bytes(engine_read_bytes),.write_bytes(engine_write_bytes),
        .stall_cycles(engine_stall_cycles),.active_cycles(engine_active_cycles),
        .dma_req_valid,.dma_req_ready,.dma_req_write,.dma_req_addr,
        .dma_req_wdata,.dma_req_wstrb,.dma_req_id,.dma_rsp_valid,
        .dma_rsp_ready,.dma_rsp_write,.dma_rsp_id,.dma_rsp_rdata,
        .dma_rsp_error);

    assign dma_req_ready=!pending && ready_gate;
    assign dma_rsp_valid=pending && delay_count==0;
    assign dma_rsp_write=pending_write;
    assign dma_rsp_id=0;
    assign dma_rsp_rdata=response_data;
    assign dma_rsp_error=0;
    always @(negedge clk) ready_gate=($time/10)%5!=0;
    always @(posedge clk) begin
        if(rst) begin
            pending<=0;pending_write<=0;delay_count<=0;
            response_data<=0;reads<=0;writes<=0;
        end else if(!pending && dma_req_valid && dma_req_ready) begin
            if(dma_req_id!=0 || dma_req_addr[3:0]!=0 ||
               dma_req_addr<BASE || dma_req_addr>BASE+32'hfff0)
                $fatal(1,"invalid DMA beat addr=%08x id=%0d",dma_req_addr,dma_req_id);
            pending<=1;pending_write<=dma_req_write;delay_count<=3;
            for(int lane=0;lane<16;lane++) begin
                if(dma_req_write) begin
                    if(dma_req_wstrb[lane])
                        memory[dma_req_addr-BASE+32'(lane)]<=dma_req_wdata[lane*8 +:8];
                end else response_data[lane*8 +:8]<=memory[dma_req_addr-BASE+32'(lane)];
            end
            if(dma_req_write) writes<=writes+1;else reads<=reads+1;
        end else if(pending) begin
            if(delay_count!=0) delay_count<=delay_count-1'b1;
            else if(dma_rsp_ready) pending<=0;
        end
    end

    task automatic mmio(input bit wr,input logic[15:0] address,
                        input logic[31:0] data,output logic[31:0] result);
        @(negedge clk);
        req_valid=1;req_write=wr;req_addr=address;req_wdata=data;
        do @(posedge clk); while(!req_ready);
        #1;
        if(!rsp_valid || rsp_error)
            $fatal(1,"MMIO fault at %04x write=%0b",address,wr);
        result=rsp_rdata;
        @(negedge clk);req_valid=0;
    endtask
    task automatic write_reg(input logic[15:0] address,
                             input logic[31:0] data);
        logic[31:0] ignored;
        mmio(1,address,data,ignored);
    endtask
    task automatic read_reg(input logic[15:0] address,
                            output logic[31:0] data);
        mmio(0,address,0,data);
    endtask

    initial begin: run
        logic[31:0] status,value;
        int attempts;
        $readmemh("case0_memory.hex",memory);
        $readmemh("case0_expected.hex",expected,0,560);
        for(int i=0;i<256;i++) memory['hd000+i]=8'(i)^8'h5a;
        repeat(5) @(negedge clk);
        rst=0;
        read_reg(16'h0140,value);
        if(value!=32'h3351_5253) $fatal(1,"S3 ID unreachable: %08x",value);
        write_reg(16'h0104,BASE+32'h1000);
        write_reg(16'h0108,BASE+32'h2000);
        write_reg(16'h010c,BASE+32'h3000);
        write_reg(16'h0110,BASE+32'h4000);
        write_reg(16'h0114,BASE+32'h5000);
        write_reg(16'h0118,BASE+32'hd000);
        write_reg(16'h011c,17);
        write_reg(16'h0120,33);
        write_reg(16'h0124,1048576);
        write_reg(16'h0128,32'h7f80_0006); // clamp=[-128,127], LUT, round mode 2
        write_reg(16'h0100,1);
        status=0;
        for(attempts=0;attempts<20000 && !(status&32'h202);attempts++)
            read_reg(16'h012c,status);
        if(attempts==20000 || (status&32'hfff)!=32'h402)
            $fatal(1,"S3 completion fault status=%08x attempts=%0d",status,attempts);
        for(int i=0;i<561;i++)
            if(memory['h2000+i] !== (expected[i]^8'h5a))
                $fatal(1,"output mismatch i=%0d got=%02x expected=%02x",
                       i,memory['h2000+i],expected[i]^8'h5a);
        for(int i=561;i<576;i++)
            if(memory['h2000+i]!==8'ha5)
                $fatal(1,"tail overwrite i=%0d",i);
        read_reg(16'h0130,value);
        if(value!=32'(3*((33+3)/4)*16+((561+3)/4)*16+256))
            $fatal(1,"read byte counter=%0d",value);
        read_reg(16'h0134,value);
        if(value!=561 || reads==0 || writes==0)
            $fatal(1,"write byte counter=%0d reads=%0d writes=%0d",value,reads,writes);
        $display("PASS tb_s3_mmio_dma CPU-style MMIO, DDR DMA, LUT, tail, counters");
        $finish;
    end
    initial begin
        repeat(300000) @(posedge clk);
        $fatal(1,"S3 integrated simulation timeout");
    end
endmodule
