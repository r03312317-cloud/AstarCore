module tb_pg_ddr_burst_bridge_queued #(
    parameter bit EXPECT_QUEUE=1
);
    timeunit 1ns; timeprecision 1ps;
    logic clk=0, rst=1;
    always #5 clk=~clk;
    logic s_req_valid,s_req_ready,s_req_write;
    logic [31:0] s_req_addr;
    logic [127:0] s_req_wdata;
    logic [15:0] s_req_wstrb;
    logic [4:0] s_req_tag;
    logic s_rsp_valid,s_rsp_ready,s_rsp_write,s_rsp_error;
    logic [127:0] s_rsp_rdata;
    logic [4:0] s_rsp_tag;
    logic [3:0] m_axi_awid,m_axi_bid,m_axi_arid,m_axi_rid;
    logic [31:0] m_axi_awaddr,m_axi_araddr;
    logic [7:0] m_axi_awlen,m_axi_arlen;
    logic [2:0] m_axi_awsize,m_axi_arsize;
    logic [1:0] m_axi_awburst,m_axi_arburst,m_axi_bresp,m_axi_rresp;
    logic m_axi_awlock,m_axi_arlock;
    logic [3:0] m_axi_awcache,m_axi_arcache;
    logic [2:0] m_axi_awprot,m_axi_arprot;
    logic m_axi_awvalid,m_axi_awready,m_axi_wlast,m_axi_wvalid,m_axi_wready;
    logic [127:0] m_axi_wdata,m_axi_rdata;
    logic [15:0] m_axi_wstrb;
    logic m_axi_bvalid,m_axi_bready,m_axi_arvalid,m_axi_arready;
    logic m_axi_rlast,m_axi_rvalid,m_axi_rready;
    logic protocol_fault,busy;
    logic [31:0] accepted_count,completed_count,burst_count;
    pg_ddr_burst_bridge #(.TAG_W(5),.MAX_BEATS(16),.FLUSH_CYCLES(5),
        .DDR_BYTES(33'h10000)) dut(.*);

    logic [127:0] memory[0:511];
    logic write_live,read_live,b_pending,allow_b;
    logic [31:0] write_addr,read_addr;
    logic [7:0] write_len,read_len;
    integer write_index,read_index,completed,cycles,physical_writes,physical_reads;
    assign allow_b=cycles>=200;
    assign m_axi_awready=!rst&&!write_live&&!b_pending&&(cycles%2!=0);
    assign m_axi_wready=!rst&&write_live&&(cycles%3!=0);
    assign m_axi_bvalid=!rst&&b_pending&&allow_b;
    assign m_axi_bid=0;
    assign m_axi_bresp=0;
    assign m_axi_arready=!rst&&!read_live&&(cycles%2!=0);
    assign m_axi_rvalid=!rst&&read_live;
    assign m_axi_rid=0;
    assign m_axi_rresp=0;
    assign m_axi_rlast=read_index==int'(read_len);
    assign m_axi_rdata=memory[(read_addr-32'h8000_0000)/16+read_index];
    always_ff @(posedge clk) begin
        if(rst)begin
            write_live<=0;read_live<=0;b_pending<=0;
            write_addr<=0;read_addr<=0;write_len<=0;read_len<=0;
            write_index<=0;read_index<=0;physical_writes<=0;physical_reads<=0;
        end else begin
            if(m_axi_awvalid&&m_axi_awready)begin
                if(m_axi_awid!=0||m_axi_awsize!=4||m_axi_awburst!=1||m_axi_awlen!=15)
                    $fatal(1,"AW_FIELDS");
                write_live<=1;write_addr<=m_axi_awaddr;write_len<=m_axi_awlen;
                write_index<=0;physical_writes<=physical_writes+1;
            end
            if(m_axi_wvalid&&m_axi_wready)begin
                if(m_axi_wlast!=(write_index==int'(write_len))||m_axi_wstrb!=16'hffff)
                    $fatal(1,"W_FIELDS");
                memory[(write_addr-32'h8000_0000)/16+write_index]<=m_axi_wdata;
                write_index<=write_index+1;
                if(m_axi_wlast)begin write_live<=0;b_pending<=1;end
            end
            if(m_axi_bvalid&&m_axi_bready)b_pending<=0;
            if(m_axi_arvalid&&m_axi_arready)begin
                if(m_axi_arid!=0||m_axi_arsize!=4||m_axi_arburst!=1||
                   m_axi_arlen!=((physical_reads<2)?8'd15:8'd0))
                    $fatal(1,"AR_FIELDS");
                if(physical_reads==2&&m_axi_araddr!=32'h8000_0ff0)
                    $fatal(1,"FIRST_4K_EDGE");
                if(physical_reads==3&&m_axi_araddr!=32'h8000_1000)
                    $fatal(1,"SECOND_4K_EDGE");
                read_live<=1;read_addr<=m_axi_araddr;read_len<=m_axi_arlen;
                read_index<=0;physical_reads<=physical_reads+1;
            end
            if(m_axi_rvalid&&m_axi_rready)begin
                read_index<=read_index+1;
                if(m_axi_rlast)read_live<=0;
            end
        end
    end
    always @(posedge clk)begin
        cycles++;
        if(cycles>5000)$fatal(1,"TIMEOUT completed=%0d accepted=%0d",completed,accepted_count);
        if(!rst&&s_rsp_valid&&s_rsp_ready)begin
            if(s_rsp_error!=(completed==64)||s_rsp_tag!=5'(completed%32)||
               s_rsp_write!=(completed<32))
                $fatal(1,"RESPONSE_ORDER completed=%0d tag=%0d",completed,s_rsp_tag);
            if(completed>=32&&completed<64&&
               s_rsp_rdata!=={112'b0,16'h4500+16'(completed%32)})
                $fatal(1,"READ_DATA completed=%0d data=%h",completed,s_rsp_rdata);
            if(completed==65&&s_rsp_rdata!==128'hfa)$fatal(1,"EDGE_DATA_0");
            if(completed==66&&s_rsp_rdata!==128'hfb)$fatal(1,"EDGE_DATA_1");
            completed++;
        end
    end
    task automatic send(input bit is_write,input integer index);
        @(negedge clk);
        s_req_valid=1;s_req_write=is_write;
        s_req_addr=32'h8000_0000+(index<16?index*16:256+(index-16)*16);
        s_req_wdata={112'b0,16'h4500+16'(index)};
        s_req_wstrb='1;s_req_tag=5'(index);
        do @(posedge clk);while(!s_req_ready);
        @(negedge clk);s_req_valid=0;
    endtask
    initial begin
        cycles=0;completed=0;s_rsp_ready=0;
        s_req_valid=0;s_req_write=0;s_req_addr=0;s_req_wdata=0;
        s_req_wstrb=0;s_req_tag=0;
        repeat(5)@(negedge clk);rst=0;
        for(int i=0;i<32;i++)send(1,i);
        repeat(10)@(negedge clk);
        if(EXPECT_QUEUE&&(cycles>=200||accepted_count!=32||completed_count!=0||
                          physical_writes!=1||!busy))
            $fatal(1,"NO_PENDING_BURST accepted=%0d completed=%0d writes=%0d",
                accepted_count,completed_count,physical_writes);
        s_rsp_ready=1;
        wait(completed==32);
        s_rsp_ready=0;
        for(int i=0;i<32;i++)send(0,i);
        repeat(20)@(negedge clk);
        if(accepted_count!=64||physical_reads<1||!busy)
            $fatal(1,"READ_QUEUE_MISSING accepted=%0d reads=%0d",accepted_count,physical_reads);
        for(int i=0;i<80;i++)begin
            @(negedge clk);s_rsp_ready=(i%3!=0);
        end
        s_rsp_ready=1;
        wait(completed==64);
        repeat(4)@(negedge clk);
        if(protocol_fault||busy||completed_count!=64||burst_count!=4||
           physical_writes!=2||physical_reads!=2)
            $fatal(1,"FINAL_STATE fault=%0b busy=%0b bursts=%0d writes=%0d reads=%0d",
                protocol_fault,busy,burst_count,physical_writes,physical_reads);
        @(negedge clk);
        s_req_valid=1;s_req_write=0;s_req_addr=32'h8001_0000;s_req_tag=0;
        do @(posedge clk);while(!s_req_ready);
        @(negedge clk);s_req_valid=0;
        wait(completed==65);
        repeat(3)@(negedge clk);
        if(protocol_fault||busy||accepted_count!=65||completed_count!=65||
           physical_writes!=2||physical_reads!=2)
            $fatal(1,"LOCAL_ERROR_FAILED");
        memory[255]=128'hfa;memory[256]=128'hfb;
        @(negedge clk);
        s_req_valid=1;s_req_write=0;s_req_addr=32'h8000_0ff0;s_req_tag=1;
        do @(posedge clk);while(!s_req_ready);
        @(negedge clk);s_req_addr=32'h8000_1000;s_req_tag=2;
        do @(posedge clk);while(!s_req_ready);
        @(negedge clk);s_req_valid=0;
        wait(completed==67);
        repeat(3)@(negedge clk);
        if(protocol_fault||busy||accepted_count!=67||completed_count!=67||
           burst_count!=6||physical_reads!=4)
            $fatal(1,"FOUR_K_BOUNDARY_FAILED");
        $display("DDR_QUEUE_PASS accepted=%0d completed=%0d bursts=%0d cycles=%0d",
            accepted_count,completed_count,burst_count,cycles);
        $finish;
    end
endmodule
