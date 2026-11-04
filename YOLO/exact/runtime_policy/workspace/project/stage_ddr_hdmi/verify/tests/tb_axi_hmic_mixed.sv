module tb_axi_hmic_mixed;
    timeunit 1ns;timeprecision 1ps;
    logic clk=0,rst=1,busy,protocol_fault;
    always #5 clk=~clk;
    logic [1:0][3:0] s_awid,s_arid,s_bid,s_rid;
    logic [1:0][31:0] s_awaddr,s_araddr;
    logic [1:0][7:0] s_awlen,s_arlen;
    logic [1:0][2:0] s_awsize,s_arsize;
    logic [1:0][1:0] s_awburst,s_arburst,s_bresp,s_rresp;
    logic [1:0][127:0] s_wdata,s_rdata;
    logic [1:0][15:0] s_wstrb;
    logic [1:0] s_awvalid,s_awready,s_wlast,s_wvalid,s_wready;
    logic [1:0] s_bvalid,s_bready,s_arvalid,s_arready;
    logic [1:0] s_rlast,s_rvalid,s_rready;
    logic [3:0] a_awid,a_bid,a_arid,a_rid;
    logic [31:0] a_awaddr,a_araddr;
    logic [7:0] a_awlen,a_arlen;
    logic [2:0] a_awsize,a_arsize;
    logic [1:0] a_awburst,a_arburst,a_bresp,a_rresp;
    logic [127:0] a_wdata,a_rdata;
    logic [15:0] a_wstrb;
    logic a_awvalid,a_awready,a_wlast,a_wvalid,a_wready;
    logic a_bvalid,a_bready,a_arvalid,a_arready;
    logic a_rlast,a_rvalid,a_rready;
    logic [7:0] h_awid,h_bid,h_arid,h_rid;
    logic [29:0] h_awaddr,h_araddr;
    logic [7:0] h_awlen,h_arlen;
    logic [2:0] h_awsize,h_arsize;
    logic [1:0] h_awburst,h_arburst,h_bresp,h_rresp;
    logic [255:0] h_wdata,h_rdata;
    logic [31:0] h_wstrb;
    logic h_awvalid,h_awready,h_wlast,h_wvalid,h_wready;
    logic h_bvalid,h_bready,h_arvalid,h_arready;
    logic h_rlast,h_rvalid,h_rready;
    soc_axi_2m_arbiter arb(
        .clk,.rst,.busy,
        .s_awid,.s_awaddr,.s_awlen,.s_awsize,.s_awburst,.s_awvalid,.s_awready,
        .s_wdata,.s_wstrb,.s_wlast,.s_wvalid,.s_wready,.s_bid,.s_bresp,
        .s_bvalid,.s_bready,.s_arid,.s_araddr,.s_arlen,.s_arsize,.s_arburst,
        .s_arvalid,.s_arready,.s_rid,.s_rdata,.s_rresp,.s_rlast,.s_rvalid,.s_rready,
        .m_awid(a_awid),.m_awaddr(a_awaddr),.m_awlen(a_awlen),
        .m_awsize(a_awsize),.m_awburst(a_awburst),.m_awvalid(a_awvalid),
        .m_awready(a_awready),.m_wdata(a_wdata),.m_wstrb(a_wstrb),
        .m_wlast(a_wlast),.m_wvalid(a_wvalid),.m_wready(a_wready),
        .m_bid(a_bid),.m_bresp(a_bresp),.m_bvalid(a_bvalid),.m_bready(a_bready),
        .m_arid(a_arid),.m_araddr(a_araddr),.m_arlen(a_arlen),
        .m_arsize(a_arsize),.m_arburst(a_arburst),.m_arvalid(a_arvalid),
        .m_arready(a_arready),.m_rid(a_rid),.m_rdata(a_rdata),
        .m_rresp(a_rresp),.m_rlast(a_rlast),.m_rvalid(a_rvalid),.m_rready(a_rready));
    soc_hmic_axi_adapter #(.DDR_BYTES(8192),.WATCHDOG_CYCLES(512)) adapter(
        .clk,.rst,.ddr_ready(1'b1),.protocol_fault,
        .s_awid(a_awid),.s_awaddr(a_awaddr),.s_awlen(a_awlen),
        .s_awsize(a_awsize),.s_awburst(a_awburst),.s_awvalid(a_awvalid),
        .s_awready(a_awready),.s_wdata(a_wdata),.s_wstrb(a_wstrb),
        .s_wlast(a_wlast),.s_wvalid(a_wvalid),.s_wready(a_wready),
        .s_bid(a_bid),.s_bresp(a_bresp),.s_bvalid(a_bvalid),.s_bready(a_bready),
        .s_arid(a_arid),.s_araddr(a_araddr),.s_arlen(a_arlen),
        .s_arsize(a_arsize),.s_arburst(a_arburst),.s_arvalid(a_arvalid),
        .s_arready(a_arready),.s_rid(a_rid),.s_rdata(a_rdata),
        .s_rresp(a_rresp),.s_rlast(a_rlast),.s_rvalid(a_rvalid),.s_rready(a_rready),
        .m_awid(h_awid),.m_awaddr(h_awaddr),.m_awlen(h_awlen),
        .m_awsize(h_awsize),.m_awburst(h_awburst),.m_awvalid(h_awvalid),
        .m_awready(h_awready),.m_wdata(h_wdata),.m_wstrb(h_wstrb),
        .m_wlast(h_wlast),.m_wvalid(h_wvalid),.m_wready(h_wready),
        .m_bid(h_bid),.m_bresp(h_bresp),.m_bvalid(h_bvalid),.m_bready(h_bready),
        .m_arid(h_arid),.m_araddr(h_araddr),.m_arlen(h_arlen),
        .m_arsize(h_arsize),.m_arburst(h_arburst),.m_arvalid(h_arvalid),
        .m_arready(h_arready),.m_rid(h_rid),.m_rdata(h_rdata),
        .m_rresp(h_rresp),.m_rlast(h_rlast),.m_rvalid(h_rvalid),.m_rready(h_rready));
    logic phys_read,phys_write,b_pending;
    logic [7:0] phys_read_id,phys_write_id;
    integer cycles=0,read_done=0,write_done=0,write0_done=0,phys_ar=0,phys_aw=0;
    logic [255:0] written_word;
    assign h_arready=!rst&&!phys_read&&!phys_write&&!b_pending;
    assign h_rvalid=!rst&&phys_read;
    assign h_rid=phys_read_id;
    assign h_rdata={2{128'h1234}};
    assign h_rresp=0;assign h_rlast=1;
    assign h_awready=!rst&&!phys_read&&!phys_write&&!b_pending;
    assign h_wready=!rst&&phys_write;
    assign h_bvalid=!rst&&b_pending;
    assign h_bid=phys_write_id;assign h_bresp=2'b10;
    always_ff @(posedge clk)begin
        if(rst)begin phys_read<=0;phys_write<=0;b_pending<=0;
            phys_read_id<=0;phys_write_id<=0;written_word<=0;end
        else begin
            if(h_arvalid&&h_arready)begin
                if(h_arid!=1||h_arlen!=0||h_arsize!=5||h_araddr!=0)
                    $fatal(1,"MIXED_AR_FIELDS");
                phys_read<=1;phys_read_id<=h_arid;phys_ar++;
            end
            if(h_rvalid&&h_rready)phys_read<=0;
            if(h_awvalid&&h_awready)begin
                if((h_awid==2&&h_awaddr!=256)||
                   (h_awid==1&&h_awaddr!=512)||
                   (h_awid!=1&&h_awid!=2)||h_awlen!=0||h_awsize!=5)
                    $fatal(1,"MIXED_AW_FIELDS");
                phys_write<=1;phys_write_id<=h_awid;phys_aw++;
            end
            if(h_wvalid&&h_wready)begin
                if(!h_wlast||h_wstrb!=32'h0000ffff||
                   (phys_write_id==2&&h_wdata[127:0]!=128'hcafebabe)||
                   (phys_write_id==1&&h_wdata[127:0]!=128'haaaa5555))
                    $fatal(1,"MIXED_W_FIELDS");
                written_word<=h_wdata;phys_write<=0;b_pending<=1;
            end
            if(h_bvalid&&h_bready)b_pending<=0;
        end
    end
    always @(posedge clk)begin
        cycles++;
        if(cycles>150)$fatal(1,"MIXED_TIMEOUT");
        if(!rst)begin
            if(!h_rready)$fatal(1,"VENDOR_RREADY_LOW");
            if(s_rvalid[0]&&s_rready[0])begin
                if(s_rid[0]!=1||s_rdata[0]!=128'h1234||s_rresp[0]!=0||!s_rlast[0])
                    $fatal(1,"READ_OWNER");
                read_done++;
            end
            if(s_bvalid[1]&&s_bready[1])begin
                if(s_bid[1]!=2||s_bresp[1]!=2'b10)$fatal(1,"WRITE_OWNER");
                write_done++;
            end
            if(s_bvalid[0]&&s_bready[0])begin
                if(s_bid[0]!=1||s_bresp[0]!=2'b10)$fatal(1,"WRITE0_OWNER");
                write0_done++;
            end
        end
    end
    initial begin
        s_awid='0;s_awaddr='0;s_awlen='0;s_awsize='0;s_awburst='0;
        s_awvalid='0;s_wdata='0;s_wstrb='0;s_wlast='0;s_wvalid='0;
        s_bready='1;s_arid='0;s_araddr='0;s_arlen='0;s_arsize='0;
        s_arburst='0;s_arvalid='0;s_rready='0;
        repeat(5)@(negedge clk);rst=0;
        @(negedge clk);s_arid[0]=1;s_araddr[0]=32'h80000000;
        s_arlen[0]=0;s_arsize[0]=4;s_arburst[0]=1;s_arvalid[0]=1;
        do @(posedge clk);while(!s_arready[0]);
        @(negedge clk);s_arvalid[0]=0;
        wait(s_rvalid[0]);
        @(negedge clk);s_awid[1]=2;s_awaddr[1]=32'h80000100;
        s_awlen[1]=0;s_awsize[1]=4;s_awburst[1]=1;s_awvalid[1]=1;
        do @(posedge clk);while(!s_awready[1]);
        @(negedge clk);s_awvalid[1]=0;
        s_wdata[1]=128'hcafebabe;s_wstrb[1]='1;s_wlast[1]=1;s_wvalid[1]=1;
        repeat(8)@(negedge clk);
        if(read_done!=0||phys_aw!=0||s_wready[1])$fatal(1,"WRITE_RAN_AHEAD_OF_READ");
        s_rready[0]=1;
        wait(read_done==1);
        do @(posedge clk);while(!s_wready[1]);
        @(negedge clk);s_wvalid[1]=0;
        wait(write_done==1);
        repeat(3)@(negedge clk);
        if(protocol_fault||busy||phys_ar!=1||phys_aw!=1)
            $fatal(1,"MIXED_FINAL_STATE");
        // Reverse direction: keep B blocked, queue the other master's read,
        // and verify no physical AR runs until the older B is consumed.
        s_bready[1]=0;
        @(negedge clk);s_awid[1]=2;s_awaddr[1]=32'h80000100;
        s_awlen[1]=0;s_awsize[1]=4;s_awburst[1]=1;s_awvalid[1]=1;
        do @(posedge clk);while(!s_awready[1]);
        @(negedge clk);s_awvalid[1]=0;
        s_wdata[1]=128'hcafebabe;s_wstrb[1]='1;s_wlast[1]=1;s_wvalid[1]=1;
        do @(posedge clk);while(!s_wready[1]);
        @(negedge clk);s_wvalid[1]=0;
        wait(s_bvalid[1]);
        @(negedge clk);s_arid[0]=1;s_araddr[0]=32'h80000000;
        s_arlen[0]=0;s_arsize[0]=4;s_arburst[0]=1;s_arvalid[0]=1;
        do @(posedge clk);while(!s_arready[0]);
        @(negedge clk);s_arvalid[0]=0;
        repeat(6)@(negedge clk);
        if(phys_ar!=1||write_done!=1||!busy)$fatal(1,"READ_RAN_AHEAD_OF_B");
        s_bready[1]=1;
        wait(write_done==2&&read_done==2);
        repeat(3)@(negedge clk);
        if(protocol_fault||busy||phys_ar!=2||phys_aw!=2)
            $fatal(1,"MIXED_REVERSE_FINAL_STATE");
        // Adjacent writes from both masters exercise two queued AW owners,
        // ordered W forwarding, and distinct BID routing.
        fork
            begin
                @(negedge clk);s_awid[0]=1;s_awaddr[0]=32'h80000200;
                s_awlen[0]=0;s_awsize[0]=4;s_awburst[0]=1;s_awvalid[0]=1;
                do @(posedge clk);while(!s_awready[0]);
                @(negedge clk);s_awvalid[0]=0;
            end
            begin
                @(negedge clk);s_awid[1]=2;s_awaddr[1]=32'h80000100;
                s_awlen[1]=0;s_awsize[1]=4;s_awburst[1]=1;s_awvalid[1]=1;
                do @(posedge clk);while(!s_awready[1]);
                @(negedge clk);s_awvalid[1]=0;
            end
        join
        s_wdata[0]=128'haaaa5555;s_wstrb[0]='1;s_wlast[0]=1;s_wvalid[0]=1;
        s_wdata[1]=128'hcafebabe;s_wstrb[1]='1;s_wlast[1]=1;s_wvalid[1]=1;
        fork
            begin
                do @(posedge clk);while(!s_wready[0]);
                @(negedge clk);s_wvalid[0]=0;
            end
            begin
                do @(posedge clk);while(!s_wready[1]);
                @(negedge clk);s_wvalid[1]=0;
            end
        join
        wait(write0_done==1&&write_done==3);
        repeat(3)@(negedge clk);
        if(protocol_fault||busy||phys_aw!=4)
            $fatal(1,"ADJACENT_WRITES_FAILED");
        $display("AXI_HMIC_MIXED_PASS cycles=%0d read=%0d write0=%0d write1=%0d",
            cycles,read_done,write0_done,write_done);
        $finish;
    end
endmodule
