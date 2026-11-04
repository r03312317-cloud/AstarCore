module tb_hmic_write_stream_benchmark;
    timeunit 1ns;timeprecision 1ps;
    localparam int BURSTS=32,BEATS=16;
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
    soc_hmic_axi_adapter #(.DDR_BYTES(32768),.WATCHDOG_CYCLES(512)) dut(
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
    logic write_live,b_pending;
    logic [7:0] write_id,write_len;
    logic [29:0] write_addr;
    integer write_index,cycles=0,logical_aw=0,logical_w=0,logical_b=0;
    integer physical_aw=0,physical_w=0,physical_idle=0,start_cycle=-1,end_cycle=-1;
    assign m_awready=!rst&&!write_live&&!b_pending;
    assign m_wready=!rst&&write_live;
    assign m_bvalid=!rst&&b_pending;
    assign m_bid=write_id;assign m_bresp=0;
    always_ff @(posedge clk)begin
        if(rst)begin write_live<=0;b_pending<=0;write_id<=0;
            write_len<=0;write_addr<=0;write_index<=0;end
        else begin
            if(m_awvalid&&m_awready)begin
                if(m_awid!=8'(physical_aw%16)||
                   m_awlen!=(physical_aw%2==0?8'd7:8'd8)||
                   m_awsize!=5||m_awburst!=1)
                    $fatal(1,"STREAM_PHYSICAL_AW_FIELDS burst=%0d",physical_aw);
                write_live<=1;write_id<=m_awid;write_len<=m_awlen;
                write_addr<=m_awaddr;write_index<=0;physical_aw++;
            end
            if(m_wvalid&&m_wready)begin
                if(m_wlast!=(write_index==int'(write_len)))
                    $fatal(1,"STREAM_PHYSICAL_WLAST");
                for(int k=0;k<32;k++)if(m_wstrb[k])
                    if(m_wdata[k*8+:8]!==8'((write_addr+30'(write_index*32+k))^30'h6d))
                        $fatal(1,"STREAM_PHYSICAL_DATA word=%0d byte=%0d",write_index,k);
                physical_w++;write_index<=write_index+1;
                if(m_wlast)begin write_live<=0;b_pending<=1;end
            end
            if(m_bvalid&&m_bready)b_pending<=0;
        end
    end
    always @(posedge clk)begin
        cycles++;
        if(cycles>5000)$fatal(1,"WRITE_STREAM_TIMEOUT aw=%0d b=%0d",logical_aw,logical_b);
        if(!rst)begin
            if(start_cycle>=0&&end_cycle<0&&!(m_wvalid&&m_wready))physical_idle++;
            if(s_awvalid&&s_awready)begin
                if(logical_aw==0)start_cycle=cycles;
                logical_aw++;
            end
            if(s_wvalid&&s_wready)logical_w++;
            if(s_bvalid&&s_bready)begin
                if(s_bid!=4'(logical_b%16)||s_bresp!=0)
                    $fatal(1,"WRITE_STREAM_B_FIELDS");
                logical_b++;
                if(logical_b==BURSTS)end_cycle=cycles;
            end
        end
    end
    initial begin
        s_awid=0;s_awaddr=0;s_awlen=15;s_awsize=4;s_awburst=1;
        s_awvalid=0;s_wdata=0;s_wstrb='1;s_wlast=0;s_wvalid=0;s_bready=1;
        repeat(5)@(negedge clk);rst=0;
        for(int i=0;i<BURSTS;i++)begin
            @(negedge clk);s_awid=4'(i%16);
            s_awaddr=32'h8000_0000+32'(i*512+(i%2)*16);s_awvalid=1;
            do @(posedge clk);while(!s_awready);
            @(negedge clk);s_awvalid=0;
            for(int b=0;b<BEATS;b++)begin
                @(negedge clk);
                for(int k=0;k<16;k++)
                    s_wdata[k*8+:8]=8'((32'(i*512+(i%2)*16+b*16+k))^32'h6d);
                s_wlast=b==BEATS-1;s_wvalid=1;
                do @(posedge clk);while(!s_wready);
                @(negedge clk);s_wvalid=0;
            end
            wait(logical_b==i+1);
        end
        repeat(2)@(negedge clk);
        if(protocol_fault||logical_w!=BURSTS*BEATS||physical_aw!=BURSTS||
           physical_w!=BURSTS*8+BURSTS/2)
            $fatal(1,"WRITE_STREAM_FINAL_STATE");
        $display("HMIC_WRITE_STREAM_PASS bursts=%0d logical_beats=%0d physical_AR=0 physical_AW=%0d physical_R=0 physical_W=%0d cycles=%0d physical_idle=%0d",
            BURSTS,logical_w,physical_aw,physical_w,end_cycle-start_cycle+1,physical_idle);
        $finish;
    end
endmodule
