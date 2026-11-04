module tb_hmic_bid_fault_reset;
    timeunit 1ns;timeprecision 1ps;
    logic clk=0,rst=1,ddr_ready=1,protocol_fault;
    always #5 clk=~clk;
    logic [3:0] s_awid,s_bid;
    logic [31:0] s_awaddr;
    logic [7:0] s_awlen;
    logic [2:0] s_awsize;
    logic [1:0] s_awburst,s_bresp;
    logic s_awvalid,s_awready,s_wlast,s_wvalid,s_wready,s_bvalid,s_bready;
    logic [127:0] s_wdata;
    logic [15:0] s_wstrb;
    logic [7:0] m_awid,m_bid;
    logic [29:0] m_awaddr;
    logic [7:0] m_awlen;
    logic [1:0] m_awburst,m_bresp;
    logic [2:0] m_awsize;
    logic m_awvalid,m_awready,m_wlast,m_wvalid,m_wready,m_bvalid,m_bready;
    logic [255:0] m_wdata;
    logic [31:0] m_wstrb;
    soc_hmic_axi_adapter #(.DDR_BYTES(8192),.WATCHDOG_CYCLES(512)) dut(
        .clk,.rst,.ddr_ready,.protocol_fault,
        .s_awid,.s_awaddr,.s_awlen,.s_awsize,.s_awburst,.s_awvalid,.s_awready,
        .s_wdata,.s_wstrb,.s_wlast,.s_wvalid,.s_wready,
        .s_bid,.s_bresp,.s_bvalid,.s_bready,
        .s_arid(4'b0),.s_araddr(32'b0),.s_arlen(8'b0),.s_arsize(3'b0),
        .s_arburst(2'b0),.s_arvalid(1'b0),.s_rready(1'b1),
        .m_awid,.m_awaddr,.m_awlen,.m_awsize,.m_awburst,.m_awvalid,.m_awready,
        .m_wdata,.m_wstrb,.m_wlast,.m_wvalid,.m_wready,
        .m_bid,.m_bresp,.m_bvalid,.m_bready,
        .m_arready(1'b1),.m_rid(8'b0),.m_rdata(256'b0),
        .m_rresp(2'b0),.m_rlast(1'b0),.m_rvalid(1'b0));
    logic write_live,b_pending,inject_bad_bid=0;
    logic [7:0] write_id;
    integer cycles=0,physical_writes=0,logical_b=0;
    assign m_awready=!rst&&!write_live&&!b_pending;
    assign m_wready=!rst&&write_live;
    assign m_bvalid=!rst&&b_pending;
    assign m_bid=inject_bad_bid?(write_id^8'h80):write_id;
    assign m_bresp=2'b10;
    always_ff @(posedge clk)begin
        if(rst)begin write_live<=0;b_pending<=0;write_id<=0;end
        else begin
            if(m_awvalid&&m_awready)begin
                if(m_awid!={4'b0,s_awid}||m_awlen!=0||m_awsize!=5||m_awaddr!=256)
                    $fatal(1,"PHYSICAL_AW_FIELDS");
                write_live<=1;write_id<=m_awid;physical_writes++;
            end
            if(m_wvalid&&m_wready)begin
                if(!m_wlast||m_wstrb!=32'h0000ffff||m_wdata[127:0]!=128'hfedcba98)
                    $fatal(1,"PHYSICAL_W_FIELDS");
                write_live<=0;b_pending<=1;
            end
            if(m_bvalid&&m_bready)b_pending<=0;
        end
    end
    always @(posedge clk)begin
        cycles++;
        if(cycles>150)$fatal(1,"BID_TEST_TIMEOUT");
        if(!rst&&s_bvalid&&s_bready)begin
            if(s_bid!=s_awid||s_bresp!=2'b10)$fatal(1,"BRESP_OR_BID_LOST");
            logical_b++;
        end
    end
    task automatic send_write(input logic [3:0] id);
        @(negedge clk);s_awid=id;s_awaddr=32'h80000100;s_awlen=0;
        s_awsize=4;s_awburst=1;s_awvalid=1;
        do @(posedge clk);while(!s_awready);
        @(negedge clk);s_awvalid=0;s_wdata=128'hfedcba98;
        s_wstrb='1;s_wlast=1;s_wvalid=1;
        do @(posedge clk);while(!s_wready);
        @(negedge clk);s_wvalid=0;
    endtask
    initial begin
        s_awid=0;s_awaddr=0;s_awlen=0;s_awsize=4;s_awburst=1;
        s_awvalid=0;s_wdata=0;s_wstrb=0;s_wlast=0;s_wvalid=0;s_bready=1;
        repeat(4)@(negedge clk);rst=0;
        send_write(1);wait(logical_b==1);
        inject_bad_bid=1;
        send_write(2);repeat(5)@(negedge clk);
        if(!protocol_fault||logical_b!=1||s_bvalid)$fatal(1,"BID_FAULT_MISSING");
        rst=1;repeat(4)@(negedge clk);inject_bad_bid=0;rst=0;
        send_write(3);wait(logical_b==2);
        repeat(2)@(negedge clk);
        if(protocol_fault||physical_writes!=3)$fatal(1,"BID_RESET_RECOVERY");
        $display("HMIC_BID_FAULT_PASS physical=%0d logical_B=%0d cycles=%0d",
            physical_writes,logical_b,cycles);
        $finish;
    end
endmodule
