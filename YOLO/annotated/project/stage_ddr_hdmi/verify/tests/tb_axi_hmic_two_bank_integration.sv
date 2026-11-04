module tb_axi_hmic_two_bank_integration #(
    parameter bit EXPECT_OVERLAP=1
);
    timeunit 1ns;timeprecision 1ps;
    logic clk=0,rst=1,busy,protocol_fault;
    always #5 clk=~clk;
    logic [1:0][3:0] s_arid,s_rid;
    logic [1:0][31:0] s_araddr;
    logic [1:0][7:0] s_arlen;
    logic [1:0][1:0] s_arburst,s_rresp;
    logic [1:0][2:0] s_arsize;
    logic [1:0][127:0] s_rdata;
    logic [1:0] s_arvalid,s_arready,s_rvalid,s_rready,s_rlast;
    logic [3:0] a_arid,a_rid;
    logic [31:0] a_araddr;
    logic [7:0] a_arlen;
    logic [2:0] a_arsize;
    logic [1:0] a_arburst,a_rresp;
    logic [127:0] a_rdata;
    logic a_arvalid,a_arready,a_rvalid,a_rready,a_rlast;
    logic [7:0] h_arid,h_rid;
    logic [29:0] h_araddr;
    logic [7:0] h_arlen;
    logic [2:0] h_arsize;
    logic [1:0] h_arburst,h_rresp;
    logic [255:0] h_rdata;
    logic h_arvalid,h_arready,h_rvalid,h_rready,h_rlast;
    logic release_reads=0;
    assign s_rready={2{release_reads}};
    soc_axi_2m_arbiter arb(
        .clk,.rst,.busy,
        .s_awid('0),.s_awaddr('0),.s_awlen('0),.s_awsize('0),
        .s_awburst('0),.s_awvalid('0),.s_wdata('0),.s_wstrb('0),
        .s_wlast('0),.s_wvalid('0),.s_bready('1),
        .s_arid,.s_araddr,.s_arlen,.s_arsize,.s_arburst,.s_arvalid,.s_arready,
        .s_rid,.s_rdata,.s_rresp,.s_rlast,.s_rvalid,.s_rready,
        .m_awready(1'b1),.m_wready(1'b1),.m_bid(4'b0),.m_bresp(2'b0),
        .m_bvalid(1'b0),.m_arid(a_arid),.m_araddr(a_araddr),.m_arlen(a_arlen),
        .m_arsize(a_arsize),.m_arburst(a_arburst),.m_arvalid(a_arvalid),
        .m_arready(a_arready),.m_rid(a_rid),.m_rdata(a_rdata),
        .m_rresp(a_rresp),.m_rlast(a_rlast),.m_rvalid(a_rvalid),.m_rready(a_rready));
    soc_hmic_axi_adapter #(.DDR_BYTES(8192),.WATCHDOG_CYCLES(512)) adapter(
        .clk,.rst,.ddr_ready(1'b1),.protocol_fault,
        .s_awid(4'b0),.s_awaddr(32'b0),.s_awlen(8'b0),.s_awsize(3'b0),
        .s_awburst(2'b0),.s_awvalid(1'b0),.s_wdata(128'b0),.s_wstrb(16'b0),
        .s_wlast(1'b0),.s_wvalid(1'b0),.s_bready(1'b1),
        .s_arid(a_arid),.s_araddr(a_araddr),.s_arlen(a_arlen),
        .s_arsize(a_arsize),.s_arburst(a_arburst),.s_arvalid(a_arvalid),
        .s_arready(a_arready),.s_rid(a_rid),.s_rdata(a_rdata),
        .s_rresp(a_rresp),.s_rlast(a_rlast),.s_rvalid(a_rvalid),.s_rready(a_rready),
        .m_awready(1'b1),.m_wready(1'b1),.m_bid(8'b0),.m_bresp(2'b0),
        .m_bvalid(1'b0),.m_arid(h_arid),.m_araddr(h_araddr),.m_arlen(h_arlen),
        .m_arsize(h_arsize),.m_arburst(h_arburst),.m_arvalid(h_arvalid),
        .m_arready(h_arready),.m_rid(h_rid),.m_rdata(h_rdata),
        .m_rresp(h_rresp),.m_rlast(h_rlast),.m_rvalid(h_rvalid),.m_rready(h_rready));
    logic read_live;
    logic [7:0] read_id,read_len;
    logic [29:0] read_addr;
    integer read_index=0;
    integer cycles=0,phys_ars=0,completed=0,second_phys_cycle=-1,first_rsp_cycle=-1;
    always @(negedge clk)if(!rst&&cycles>=60)release_reads=1;
    assign h_arready=!rst&&!read_live;
    assign h_rvalid=!rst&&read_live&&(cycles%3!=0);
    assign h_rid=read_id;
    assign h_rdata=(read_addr==0)?{2{128'h1111}}:{2{128'h2222}};
    assign h_rresp=0;
    assign h_rlast=read_index==int'(read_len);
    always_ff @(posedge clk)begin
        if(rst)begin read_live<=0;read_id<=0;read_len<=0;read_addr<=0;read_index<=0;end
        else begin
            if(h_arvalid&&h_arready)begin
                if(h_arid!=8'(phys_ars+1)||
                   h_arlen!=((phys_ars==0)?8'd0:8'd8)||h_arsize!=5)
                    $fatal(1,"PHYSICAL_ORDER");
                if(phys_ars==1)second_phys_cycle=cycles;
                phys_ars++;read_live<=1;read_id<=h_arid;read_len<=h_arlen;
                read_addr<=h_araddr;read_index<=0;
            end
            if(h_rvalid&&h_rready)begin
                read_index<=read_index+1;
                if(h_rlast)read_live<=0;
            end
        end
    end
    always @(posedge clk)begin
        cycles++;
        if(cycles>100)$fatal(1,"INTEGRATION_TIMEOUT");
        if(!rst)begin
            if(!h_rready)$fatal(1,"HMIC_RREADY_LOW");
            if(s_rvalid[0]&&s_rready[0])begin
                if(completed!=0||s_rid[0]!=1||s_rdata[0]!=128'h1111||
                   s_rresp[0]!=0||!s_rlast[0])$fatal(1,"MASTER0_RESPONSE");
                first_rsp_cycle=cycles;completed++;
            end
            if(s_rvalid[1]&&s_rready[1])begin
                if(completed<1||completed>16||s_rid[1]!=2||
                   s_rdata[1]!=128'h2222||s_rresp[1]!=0||
                   s_rlast[1]!=(completed==16))$fatal(1,"MASTER1_RESPONSE beat=%0d",completed);
                completed++;
            end
        end
    end
    initial begin
        s_arid='0;s_araddr='0;s_arlen='0;s_arsize='0;
        s_arburst='0;s_arvalid='0;
        repeat(5)@(negedge clk);rst=0;
        @(negedge clk);s_arid[0]=1;s_araddr[0]=32'h80000000;
        s_arsize[0]=4;s_arburst[0]=1;s_arvalid[0]=1;
        do @(posedge clk);while(!s_arready[0]);
        @(negedge clk);s_arvalid[0]=0;
        wait(s_rvalid[0]);
        @(negedge clk);s_arid[1]=2;s_araddr[1]=32'h80000030;
        s_arlen[1]=15;s_arsize[1]=4;s_arburst[1]=1;s_arvalid[1]=1;
        do @(posedge clk);while(!s_arready[1]);
        @(negedge clk);s_arvalid[1]=0;
        if(EXPECT_OVERLAP)repeat(12)@(negedge clk);
        if(EXPECT_OVERLAP&&(phys_ars!=2||completed!=0))
            $fatal(1,"NO_PHYSICAL_OVERLAP phys=%0d completed=%0d",
                phys_ars,completed);
        wait(completed==17);
        repeat(2)@(negedge clk);
        if(protocol_fault||busy||
           (EXPECT_OVERLAP&&second_phys_cycle>=first_rsp_cycle))
            $fatal(1,"INTEGRATION_ORDER_FAULT");
        $display("AXI_HMIC_TWO_BANK_PASS second_physical=%0d first_logical_response=%0d cycles=%0d",
            second_phys_cycle,first_rsp_cycle,cycles);
        $finish;
    end
endmodule
