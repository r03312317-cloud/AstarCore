module tb_hmic_stream_benchmark;
    timeunit 1ns;timeprecision 1ps;
    localparam int BURSTS=32,BEATS=16;
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
    logic [1:0] m_arburst,m_rresp;
    logic [2:0] m_arsize;
    logic m_arvalid,m_arready,m_rvalid,m_rready,m_rlast;
    logic [255:0] m_rdata;
    soc_hmic_axi_adapter #(.DDR_BYTES(32768),.WATCHDOG_CYCLES(512)) dut(
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
    logic [7:0] read_id,read_len;
    logic [29:0] read_addr;
    integer read_index,cycles=0,logical_ar=0,logical_beats=0;
    integer physical_ar=0,physical_r=0,physical_idle=0,start_cycle=-1,end_cycle=-1;
    function automatic logic [255:0] pattern(input logic [29:0] a);
        logic [255:0] d;
        for(int k=0;k<32;k++)d[k*8+:8]=8'((a+30'(k))^30'h6d);
        return d;
    endfunction
    assign m_arready=!rst&&!read_live;
    assign m_rvalid=!rst&&read_live;
    assign m_rid=read_id;assign m_rresp=0;
    assign m_rlast=read_index==int'(read_len);
    assign m_rdata=pattern(read_addr+30'(read_index*32));
    always_ff @(posedge clk)begin
        if(rst)begin read_live<=0;read_id<=0;read_len<=0;read_addr<=0;read_index<=0;end
        else begin
            if(m_arvalid&&m_arready)begin
                if(m_arid!=8'(physical_ar%16)||m_arlen!=(physical_ar%2==0?8'd7:8'd8)||
                   m_arsize!=5||m_arburst!=1)
                    $fatal(1,"STREAM_PHYSICAL_AR_FIELDS burst=%0d",physical_ar);
                read_live<=1;read_id<=m_arid;read_len<=m_arlen;
                read_addr<=m_araddr;read_index<=0;physical_ar++;
            end
            if(m_rvalid&&m_rready)begin
                physical_r++;read_index<=read_index+1;
                if(m_rlast)read_live<=0;
            end
        end
    end
    always @(posedge clk)begin
        cycles++;
        if(cycles>5000)$fatal(1,"STREAM_TIMEOUT ar=%0d rsp=%0d",logical_ar,logical_beats);
        if(!rst)begin
            if(!m_rready)$fatal(1,"VENDOR_RREADY_LOW");
            if(start_cycle>=0&&end_cycle<0&&!(m_rvalid&&m_rready))physical_idle++;
            if(s_arvalid&&s_arready)begin
                if(logical_ar==0)start_cycle=cycles;
                logical_ar++;
            end
            if(s_rvalid&&s_rready)begin
                int burst,beat;
                logic [31:0] addr;
                burst=logical_beats/BEATS;beat=logical_beats%BEATS;
                addr=32'h8000_0000+32'(burst*512+(burst%2)*16+beat*16);
                if(s_rid!=4'(burst%16)||s_rresp!=0||s_rlast!=(beat==BEATS-1))
                    $fatal(1,"STREAM_LOGICAL_FIELDS burst=%0d beat=%0d",burst,beat);
                for(int k=0;k<16;k++)
                    if(s_rdata[k*8+:8]!==8'(((addr-32'h8000_0000)+32'(k))^32'h6d))
                        $fatal(1,"STREAM_LOGICAL_DATA burst=%0d beat=%0d byte=%0d",burst,beat,k);
                logical_beats++;
                if(logical_beats==BURSTS*BEATS)end_cycle=cycles;
            end
        end
    end
    initial begin
        s_arid=0;s_araddr=0;s_arlen=15;s_arsize=4;s_arburst=1;
        s_arvalid=0;s_rready=1;
        repeat(5)@(negedge clk);rst=0;
        for(int i=0;i<BURSTS;i++)begin
            @(negedge clk);s_arid=4'(i%16);
            s_araddr=32'h8000_0000+32'(i*512+(i%2)*16);s_arvalid=1;
            do @(posedge clk);while(!s_arready);
            @(negedge clk);s_arvalid=0;
        end
        wait(logical_beats==BURSTS*BEATS);
        repeat(2)@(negedge clk);
        if(protocol_fault||physical_ar!=BURSTS||physical_r!=BURSTS*8+BURSTS/2)
            $fatal(1,"STREAM_FINAL_STATE");
        $display("HMIC_STREAM_PASS bursts=%0d logical_beats=%0d physical_AR=%0d physical_AW=0 physical_R=%0d physical_W=0 cycles=%0d physical_idle=%0d",
            BURSTS,logical_beats,physical_ar,physical_r,end_cycle-start_cycle+1,physical_idle);
        $finish;
    end
endmodule
