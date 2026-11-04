module tb_hmic_two_bank_read;
    timeunit 1ns;timeprecision 1ps;
    logic clk=0,rst=1,ddr_ready=1,protocol_fault;
    always #5 clk=~clk;
    logic [3:0] s_arid,s_rid;
    logic [31:0] s_araddr;
    logic [7:0] s_arlen;
    logic [2:0] s_arsize;
    logic [1:0] s_arburst,s_rresp;
    logic s_arvalid,s_arready,s_rvalid,s_rready,s_rlast;
    logic [127:0] s_rdata;
    logic [7:0] m_arid,m_rid;
    logic [29:0] m_araddr;
    logic [7:0] m_arlen;
    logic [2:0] m_arburst,m_rresp;
    logic [2:0] m_arsize;
    logic m_arvalid,m_arready,m_rvalid,m_rready,m_rlast;
    logic [255:0] m_rdata;
    soc_hmic_axi_adapter #(.DDR_BYTES(8192),.WATCHDOG_CYCLES(512)) dut(
        .clk,.rst,.ddr_ready,.protocol_fault,
        .s_awid(4'b0),.s_awaddr(32'b0),.s_awlen(8'b0),.s_awsize(3'b0),
        .s_awburst(2'b0),.s_awvalid(1'b0),.s_wdata(128'b0),.s_wstrb(16'b0),
        .s_wlast(1'b0),.s_wvalid(1'b0),.s_bready(1'b1),
        .s_arid,.s_araddr,.s_arlen,.s_arsize,.s_arburst,.s_arvalid,.s_arready,
        .s_rid,.s_rdata,.s_rresp,.s_rlast,.s_rvalid,.s_rready,
        .m_awready(1'b1),.m_wready(1'b1),.m_bid(8'b0),.m_bresp(2'b0),
        .m_bvalid(1'b0),.m_arid,.m_araddr,.m_arlen,.m_arsize,.m_arburst,
        .m_arvalid,.m_arready,.m_rid,.m_rdata,.m_rresp,.m_rlast,.m_rvalid,.m_rready);
    logic read_live;
    logic [7:0] read_id;
    logic [29:0] read_addr;
    integer cycles=0,phys_ars=0,logical_rs=0,second_accept=-1,first_rsp=-1;
    logic inject_rid=0,suppress_r=0;
    assign m_arready=!rst&&!read_live;
    assign m_rvalid=!rst&&read_live&&!suppress_r;
    assign m_rid=(inject_rid&&read_id==6)?(read_id^8'h80):read_id;
    assign m_rlast=1'b1;
    assign m_rresp=0;
    assign m_rdata=(read_addr==0)?256'h1111:256'h2222;
    always_ff @(posedge clk)begin
        if(rst)begin read_live<=0;read_id<=0;read_addr<=0;end
        else begin
            if(m_arvalid&&m_arready)begin
                if(m_arlen!=0||m_arsize!=5||m_arburst!=1||m_arid!={4'b0,s_arid})
                    $fatal(1,"BAD_HMIC_AR");
                read_live<=1;read_id<=m_arid;read_addr<=m_araddr;phys_ars++;
            end
            if(m_rvalid&&m_rready)read_live<=0;
        end
    end
    always @(posedge clk)begin
        cycles++;
        if(cycles>1500)$fatal(1,"TWO_BANK_TIMEOUT phys=%0d logical=%0d second_accept=%0d",
            phys_ars,logical_rs,second_accept);
        if(rst)logical_rs=0;
        else begin
            if(!m_rready)$fatal(1,"VENDOR_RREADY_LOW");
            if(s_rvalid&&s_rready)begin
                if(s_rid!=4'(logical_rs+1)||
                   (logical_rs<3&&s_rdata!=(logical_rs==0?128'h1111:128'h2222))||
                   s_rresp!=((logical_rs==3)?2'b11:2'b00)||!s_rlast)
                    $fatal(1,"LOGICAL_RESPONSE_ORDER beat=%0d",logical_rs);
                if(logical_rs==0)first_rsp=cycles;
                logical_rs++;
            end
        end
    end
    initial begin
        s_arid=0;s_araddr=0;s_arlen=0;s_arsize=4;s_arburst=1;
        s_arvalid=0;s_rready=0;
        repeat(5)@(negedge clk);rst=0;
        @(negedge clk);s_arid=1;s_araddr=32'h8000_0000;s_arvalid=1;
        do @(posedge clk);while(!s_arready);
        @(negedge clk);s_arvalid=0;
        wait(s_rvalid);
        @(negedge clk);s_arid=2;s_araddr=32'h8000_0020;s_arvalid=1;
        repeat(12)begin
            @(posedge clk);
            if(s_arready)begin second_accept=cycles;break;end
        end
        if(second_accept<0)$fatal(1,"SECOND_AR_NOT_BUFFERED");
        @(negedge clk);s_arvalid=0;
        repeat(12)@(negedge clk);
        if(phys_ars!=2||logical_rs!=0)$fatal(1,"SECOND_PHYSICAL_NOT_OVERLAPPED");
        // Both banks are occupied, but no physical transaction remains. A
        // prolonged upstream stall must neither overwrite nor trip watchdog.
        repeat(600)@(negedge clk);
        if(protocol_fault||phys_ars!=2||logical_rs!=0)
            $fatal(1,"SECOND_BANK_BACKPRESSURE_FAULT");
        s_rready=1;
        wait(logical_rs==2);
        repeat(2)@(negedge clk);
        if(protocol_fault||first_rsp<=second_accept)$fatal(1,"OVERLAP_ORDER_FAULT");
        // Illegal queued AR returns DECERR after the older buffered read,
        // without consuming a physical HMIC transaction or poisoning state.
        s_rready=0;
        @(negedge clk);s_arid=3;s_araddr=32'h8000_0040;s_arsize=4;s_arvalid=1;
        do @(posedge clk);while(!s_arready);
        @(negedge clk);s_arvalid=0;
        wait(s_rvalid);
        @(negedge clk);s_arid=4;s_araddr=32'h8000_0060;s_arsize=3;s_arvalid=1;
        do @(posedge clk);while(!s_arready);
        @(negedge clk);s_arvalid=0;
        repeat(6)@(negedge clk);
        if(phys_ars!=3)$fatal(1,"ILLEGAL_PREFETCH_ISSUED_PHYSICAL");
        s_rready=1;
        wait(logical_rs==4);
        repeat(2)@(negedge clk);
        if(protocol_fault||phys_ars!=3)$fatal(1,"ILLEGAL_PREFETCH_FAULT");
        // A malformed second RID faults the whole shared transaction domain;
        // common reset must clear it before new work is admitted.
        s_rready=0;
        @(negedge clk);s_arid=5;s_araddr=32'h8000_0000;s_arsize=4;s_arvalid=1;
        do @(posedge clk);while(!s_arready);
        @(negedge clk);s_arvalid=0;
        wait(s_rvalid);
        inject_rid=1;
        @(negedge clk);s_arid=6;s_araddr=32'h8000_0020;s_arvalid=1;
        do @(posedge clk);while(!s_arready);
        @(negedge clk);s_arvalid=0;
        repeat(6)@(negedge clk);
        if(!protocol_fault)$fatal(1,"PREFETCH_RID_FAULT_MISSING");
        rst=1;repeat(4)@(negedge clk);inject_rid=0;rst=0;
        @(negedge clk);s_arid=1;s_araddr=32'h8000_0000;s_arvalid=1;
        do @(posedge clk);while(!s_arready);
        @(negedge clk);s_arvalid=0;s_rready=1;
        wait(logical_rs==1);
        repeat(2)@(negedge clk);
        if(protocol_fault)$fatal(1,"RESET_RECOVERY_FAILED");
        // Common reset in the middle of the second physical read discards
        // both logical slots; a fresh request must not see stale data/ID.
        s_rready=0;
        @(negedge clk);s_arid=5;s_araddr=32'h8000_0000;s_arvalid=1;
        do @(posedge clk);while(!s_arready);
        @(negedge clk);s_arvalid=0;
        wait(s_rvalid);
        suppress_r=1;
        @(negedge clk);s_arid=6;s_araddr=32'h8000_0020;s_arvalid=1;
        do @(posedge clk);while(!s_arready);
        @(negedge clk);s_arvalid=0;
        repeat(4)@(negedge clk);
        if(!read_live||dut.prefetch_state!=2)
            $fatal(1,"RESET_DID_NOT_HIT_PREFETCH");
        rst=1;repeat(4)@(negedge clk);suppress_r=0;rst=0;
        if(protocol_fault||s_rvalid)$fatal(1,"STALE_POST_RESET_RESPONSE");
        @(negedge clk);s_arid=1;s_araddr=32'h8000_0000;s_arvalid=1;
        do @(posedge clk);while(!s_arready);
        @(negedge clk);s_arvalid=0;s_rready=1;
        wait(logical_rs==1);
        repeat(2)@(negedge clk);
        if(protocol_fault)$fatal(1,"MID_PREFETCH_RESET_RECOVERY_FAILED");
        $display("HMIC_TWO_BANK_PASS second_accept=%0d first_rsp=%0d physical=%0d cycles=%0d",
            second_accept,first_rsp,phys_ars,cycles);
        $finish;
    end
endmodule
