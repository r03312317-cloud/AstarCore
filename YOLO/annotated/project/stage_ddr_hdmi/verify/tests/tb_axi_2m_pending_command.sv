module tb_axi_2m_pending_command #(
    parameter bit EXPECT_QUEUE=1
);
    timeunit 1ns; timeprecision 1ps;
    logic clk=0,rst=1,busy;
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
    logic [3:0] m_awid,m_bid,m_arid,m_rid;
    logic [31:0] m_awaddr,m_araddr;
    logic [7:0] m_awlen,m_arlen;
    logic [2:0] m_awsize,m_arsize;
    logic [1:0] m_awburst,m_arburst,m_bresp,m_rresp;
    logic [127:0] m_wdata,m_rdata;
    logic [15:0] m_wstrb;
    logic m_awvalid,m_awready,m_wlast,m_wvalid,m_wready;
    logic m_bvalid,m_bready,m_arvalid,m_arready;
    logic m_rlast,m_rvalid,m_rready;
    soc_axi_2m_arbiter dut(.*);
    integer cycles=0,aw_count=0,w_count=0,b_count=0,ar_count=0,r_count=0;
    integer pending_accept_cycle=-1,first_b_cycle=-1;
    integer second_accept_cycle=-1,second_r_cycle=-1;
    integer downstream_ar_cycle=-1,downstream_aw2_cycle=-1;
    logic first_b_pending=0,read_pending=0;
    assign m_awready=1'b1;
    assign m_wready=1'b1;
    assign m_arready=1'b1;
    assign m_bvalid=first_b_pending&&(aw_count>1||cycles>=50);
    assign m_bid=(aw_count==1)?4'h1:4'h3;
    assign m_bresp=(aw_count==1)?2'b10:2'b00;
    assign m_rvalid=read_pending&&(ar_count==1||cycles>=100);
    assign m_rid=(ar_count==1)?4'h2:4'h4;
    assign m_rdata=(ar_count==1)?128'h0123456789abcdef:128'hdeadbeef;
    assign m_rresp=2'b00;assign m_rlast=1'b1;
    always @(posedge clk)begin
        cycles++;
        if(cycles>250)$fatal(1,"TIMEOUT aw=%0d ar=%0d b=%0d r=%0d",
            aw_count,ar_count,b_count,r_count);
        if(!rst)begin
            if(m_awvalid&&m_arvalid)$fatal(1,"TWO_DOWNSTREAM_COMMANDS");
            if(s_arvalid[1]&&s_arready[1])pending_accept_cycle=cycles;
            if(s_awvalid[1]&&s_awready[1])second_accept_cycle=cycles;
            if(m_awvalid&&m_awready)begin
                if((aw_count==0&&(m_awid!=1||m_awaddr!=32'h80000100))||
                   (aw_count==1&&(m_awid!=3||m_awaddr!=32'h80000300))||
                   m_awlen!=0||m_awsize!=4)
                    $fatal(1,"AW_ROUTING");
                if(aw_count==1)downstream_aw2_cycle=cycles;
                aw_count++;
            end
            if(m_wvalid&&m_wready)begin
                if((w_count==0&&m_wdata!=128'hcafebabe)||
                   (w_count==1&&m_wdata!=128'h87654321)||
                   m_wstrb!=16'hffff||!m_wlast)
                    $fatal(1,"W_ROUTING");
                w_count++;first_b_pending<=1;
            end
            if(m_bvalid&&m_bready)begin
                if((b_count==0&&(!s_bvalid[0]||s_bvalid[1]||
                                 s_bid[0]!=1||s_bresp[0]!=2'b10))||
                   (b_count==1&&(!s_bvalid[1]||s_bvalid[0]||
                                 s_bid[1]!=3||s_bresp[1]!=0)))
                    $fatal(1,"B_ROUTING");
                if(b_count==0)first_b_cycle=cycles;
                b_count++;first_b_pending<=0;
            end
            if(m_arvalid&&m_arready)begin
                if((ar_count==0&&(m_arid!=2||m_araddr!=32'h80000200))||
                   (ar_count==1&&(m_arid!=4||m_araddr!=32'h80000400))||
                   m_arlen!=0||m_arsize!=4)
                    $fatal(1,"AR_ROUTING");
                if(ar_count==0)downstream_ar_cycle=cycles;
                ar_count++;read_pending<=1;
            end
            if(m_rvalid&&m_rready)begin
                if((r_count==0&&(!s_rvalid[1]||s_rvalid[0]||s_rid[1]!=2||
                                 s_rdata[1]!=128'h0123456789abcdef||!s_rlast[1]))||
                   (r_count==1&&(!s_rvalid[0]||s_rvalid[1]||s_rid[0]!=4||
                                 s_rdata[0]!=128'hdeadbeef||!s_rlast[0])))
                    $fatal(1,"R_ROUTING");
                if(r_count==1)second_r_cycle=cycles;
                r_count++;read_pending<=0;
            end
        end
    end
    initial begin
        s_awid='0;s_awaddr='0;s_awlen='0;s_awsize='0;s_awburst='0;
        s_awvalid='0;s_wdata='0;s_wstrb='0;s_wlast='0;s_wvalid='0;
        s_bready='0;s_arid='0;s_araddr='0;s_arlen='0;
        s_arsize='0;s_arburst='0;s_arvalid='0;s_rready='0;
        repeat(5)@(negedge clk);rst=0;
        @(negedge clk);
        s_awid[0]=1;s_awaddr[0]=32'h80000100;s_awlen[0]=0;
        s_awsize[0]=4;s_awburst[0]=1;s_awvalid[0]=1;
        do @(posedge clk);while(!s_awready[0]);
        @(negedge clk);s_awvalid[0]=0;
        wait(aw_count==1);
        @(negedge clk);
        s_wdata[0]=128'hcafebabe;s_wstrb[0]='1;s_wlast[0]=1;s_wvalid[0]=1;
        do @(posedge clk);while(!s_wready[0]);
        @(negedge clk);s_wvalid[0]=0;
        s_bready[0]=1;
        s_arid[1]=2;s_araddr[1]=32'h80000200;s_arlen[1]=0;
        s_arsize[1]=4;s_arburst[1]=1;s_arvalid[1]=1;
        do @(posedge clk);while(!s_arready[1]);
        @(negedge clk);s_arvalid[1]=0;s_rready[1]=1;
        wait(r_count==1);
        repeat(3)@(negedge clk);
        if(aw_count!=1||w_count!=1||b_count!=1||ar_count!=1||r_count!=1||busy)
            $fatal(1,"FINAL_COUNTS aw=%0d w=%0d b=%0d ar=%0d r=%0d",
                aw_count,w_count,b_count,ar_count,r_count);
        if(EXPECT_QUEUE&&!(pending_accept_cycle>=0&&pending_accept_cycle<first_b_cycle))
            $fatal(1,"NO_COMMAND_QUEUE pending=%0d B=%0d",
                pending_accept_cycle,first_b_cycle);
        @(negedge clk);
        s_arid[0]=4;s_araddr[0]=32'h80000400;s_arlen[0]=0;
        s_arsize[0]=4;s_arburst[0]=1;s_arvalid[0]=1;s_rready[0]=1;
        do @(posedge clk);while(!s_arready[0]);
        @(negedge clk);s_arvalid[0]=0;
        wait(ar_count==2);
        @(negedge clk);
        s_awid[1]=3;s_awaddr[1]=32'h80000300;s_awlen[1]=0;
        s_awsize[1]=4;s_awburst[1]=1;s_awvalid[1]=1;
        do @(posedge clk);while(!s_awready[1]);
        @(negedge clk);
        s_awvalid[1]=0;s_wdata[1]=128'h87654321;s_wstrb[1]='1;
        s_wlast[1]=1;s_wvalid[1]=1;s_bready[1]=1;
        if(EXPECT_QUEUE)repeat(5)begin
            @(posedge clk);
            if(s_wready[1]&&r_count<2)$fatal(1,"QUEUED_W_ACCEPTED_EARLY");
        end
        wait(r_count==2);
        do @(posedge clk);while(!s_wready[1]);
        @(negedge clk);s_wvalid[1]=0;
        wait(b_count==2);
        repeat(3)@(negedge clk);
        if(aw_count!=2||w_count!=2||b_count!=2||ar_count!=2||r_count!=2||busy)
            $fatal(1,"SECOND_FINAL_COUNTS");
        if(EXPECT_QUEUE&&!(second_accept_cycle>=0&&second_accept_cycle<second_r_cycle))
            $fatal(1,"NO_REVERSE_QUEUE pending=%0d R=%0d",
                second_accept_cycle,second_r_cycle);
        if(downstream_ar_cycle<=first_b_cycle||downstream_aw2_cycle<=second_r_cycle)
            $fatal(1,"DOWNSTREAM_SINGLE_OUTSTANDING_BROKEN");
        $display("AXI_PENDING_PASS ar_pending=%0d first_B=%0d downstream_AR=%0d aw_pending=%0d second_R=%0d downstream_AW=%0d final=%0d",
            pending_accept_cycle,first_b_cycle,downstream_ar_cycle,
            second_accept_cycle,second_r_cycle,downstream_aw2_cycle,cycles);
        $finish;
    end
endmodule
