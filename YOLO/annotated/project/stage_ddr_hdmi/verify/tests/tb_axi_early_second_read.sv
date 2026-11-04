module tb_axi_early_second_read;
    timeunit 1ns;timeprecision 1ps;
    logic clk=0,rst=1,busy;
    always #5 clk=~clk;
    logic [1:0][3:0] s_arid,s_rid;
    logic [1:0][31:0] s_araddr;
    logic [1:0][7:0] s_arlen;
    logic [1:0][2:0] s_arsize;
    logic [1:0][1:0] s_arburst,s_rresp;
    logic [1:0][127:0] s_rdata;
    logic [1:0] s_arvalid,s_arready,s_rvalid,s_rready,s_rlast;
    logic [3:0] m_arid,m_rid;
    logic [31:0] m_araddr;
    logic [7:0] m_arlen;
    logic [2:0] m_arsize;
    logic [1:0] m_arburst,m_rresp;
    logic m_arvalid,m_arready,m_rvalid,m_rready,m_rlast;
    logic [127:0] m_rdata;
    soc_axi_2m_arbiter dut(
        .clk,.rst,.busy,
        .s_awid('0),.s_awaddr('0),.s_awlen('0),.s_awsize('0),
        .s_awburst('0),.s_awvalid('0),.s_wdata('0),.s_wstrb('0),
        .s_wlast('0),.s_wvalid('0),.s_bready('1),
        .s_arid,.s_araddr,.s_arlen,.s_arsize,.s_arburst,.s_arvalid,.s_arready,
        .s_rid,.s_rdata,.s_rresp,.s_rlast,.s_rvalid,.s_rready,
        .m_awready(1'b1),.m_wready(1'b1),.m_bid(4'b0),.m_bresp(2'b0),
        .m_bvalid(1'b0),.m_arid,.m_araddr,.m_arlen,.m_arsize,.m_arburst,
        .m_arvalid,.m_arready,.m_rid,.m_rdata,.m_rresp,.m_rlast,.m_rvalid,.m_rready);
    integer cycles=0,downstream_ars=0,r_count=0,second_ar_cycle=-1,first_rsp_cycle=-1;
    logic [1:0] issued;
    assign m_arready=1'b1;
    assign m_rvalid=downstream_ars>r_count;
    assign m_rid=(r_count==0)?1:2;
    assign m_rdata=(r_count==0)?128'h1111:128'h2222;
    assign m_rresp=0;
    assign m_rlast=1;
    always @(posedge clk)begin
        cycles++;
        if(cycles>100)$fatal(1,"EARLY_READ_TIMEOUT ar=%0d r=%0d",downstream_ars,r_count);
        if(!rst)begin
            if(m_arvalid&&m_arready)begin
                if(m_arid!=4'(downstream_ars+1))$fatal(1,"AR_ID_ORDER");
                if(downstream_ars==1)second_ar_cycle=cycles;
                downstream_ars++;
            end
            if(m_rvalid&&m_rready)begin
                if(!s_rvalid[r_count]||s_rid[r_count]!=4'(r_count+1)||
                   s_rdata[r_count]!=(r_count==0?128'h1111:128'h2222))
                    $fatal(1,"R_OWNER_OR_DATA");
                if(r_count==0)first_rsp_cycle=cycles;
                r_count++;
            end
        end
    end
    initial begin
        s_arid='0;s_araddr='0;s_arlen='0;s_arsize='0;
        s_arburst='0;s_arvalid='0;s_rready='0;
        repeat(5)@(negedge clk);rst=0;
        @(negedge clk);s_arid[0]=1;s_araddr[0]=32'h80000000;
        s_arsize[0]=4;s_arburst[0]=1;s_arvalid[0]=1;
        do @(posedge clk);while(!s_arready[0]);
        @(negedge clk);s_arvalid[0]=0;
        wait(downstream_ars==1);
        @(negedge clk);s_arid[1]=2;s_araddr[1]=32'h80000020;
        s_arsize[1]=4;s_arburst[1]=1;s_arvalid[1]=1;
        do @(posedge clk);while(!s_arready[1]);
        @(negedge clk);s_arvalid[1]=0;
        repeat(10)@(negedge clk);
        if(downstream_ars!=2||r_count!=0)$fatal(1,"SECOND_AR_NOT_SENT_EARLY");
        s_rready='1;
        wait(r_count==2);
        repeat(2)@(negedge clk);
        if(busy||second_ar_cycle>=first_rsp_cycle)$fatal(1,"RESPONSE_ORDER");
        $display("AXI_EARLY_READ_PASS second_AR=%0d first_R=%0d cycles=%0d",
            second_ar_cycle,first_rsp_cycle,cycles);
        $finish;
    end
endmodule
