module tb_hmic_two_bank_multibeat;
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
    logic [1:0] m_arburst,m_rresp;
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
    logic [7:0] read_id,read_len;
    logic [29:0] read_addr;
    integer read_index,cycles=0,phys_ars=0,physical_done=0,logical_beats=0;
    logic [31:0] rng=32'h61e09753;
    function automatic logic [255:0] pattern(input logic [29:0] a);
        logic [255:0] d;
        for(int k=0;k<32;k++)d[k*8+:8]=8'((a+30'(k))^30'h5a);
        return d;
    endfunction
    assign m_arready=!rst&&!read_live&&rng[0];
    assign m_rvalid=!rst&&read_live&&rng[2];
    assign m_rid=read_id;
    assign m_rlast=read_index==int'(read_len);
    assign m_rresp=(read_id==2&&read_index==2)?2'b10:2'b00;
    assign m_rdata=pattern(read_addr+30'(read_index*32));
    always_ff @(posedge clk)begin
        if(rst)begin read_live<=0;read_id<=0;read_len<=0;read_addr<=0;read_index<=0;end
        else begin
            if(m_arvalid&&m_arready)begin
                if(m_arsize!=5||m_arburst!=1||m_arlen>8||m_araddr[4:0]!=0)
                    $fatal(1,"BAD_HMIC_AR");
                read_live<=1;read_id<=m_arid;read_len<=m_arlen;
                read_addr<=m_araddr;read_index<=0;phys_ars++;
            end
            if(m_rvalid&&m_rready)begin
                read_index<=read_index+1;
                if(m_rlast)begin read_live<=0;physical_done++;end
            end
        end
    end
    always @(posedge clk)begin
        cycles++;
        rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        if(cycles>10000)$fatal(1,"MULTIBEAT_TIMEOUT pair=%0d phys=%0d done=%0d",
            logical_beats,phys_ars,physical_done);
        if(!rst)begin
            if(!m_rready)$fatal(1,"VENDOR_RREADY_LOW");
            if(s_rvalid&&s_rready)logical_beats++;
        end
    end
    task automatic send_ar(input logic [3:0] id,input logic [31:0] addr,input int n);
        @(negedge clk);s_arid=id;s_araddr=addr;s_arlen=8'(n-1);s_arvalid=1;
        do @(posedge clk);while(!s_arready);
        @(negedge clk);s_arvalid=0;
    endtask
    task automatic drain(input logic [3:0] id,input logic [31:0] addr,input int n);
        for(int b=0;b<n;b++)begin
            repeat(int'(rng[2:1]))@(negedge clk);
            @(negedge clk);s_rready=1;
            do @(posedge clk);while(!s_rvalid);
            if(s_rid!=id||s_rresp!=((id==2&&((int'(addr[4])+b)/2)==2)?2'b10:2'b00)||
               s_rlast!=(b==n-1))
                $fatal(1,"LOGICAL_FIELDS id=%0d beat=%0d",id,b);
            for(int k=0;k<16;k++)
                if(s_rdata[k*8+:8]!==8'(((addr-32'h8000_0000)+32'(b*16+k))^32'h5a))
                    $fatal(1,"LOGICAL_DATA id=%0d beat=%0d byte=%0d",id,b,k);
            @(negedge clk);s_rready=0;
        end
    endtask
    task automatic run_pair(input logic [31:0] a0,input int n1,
                            input logic [31:0] a1,input int n2);
        int target=physical_done+2;
        send_ar(1,a0,n1);
        wait(s_rvalid);
        send_ar(2,a1,n2);
        wait(physical_done==target);
        if(phys_ars!=target||protocol_fault)
            $fatal(1,"NO_DUAL_PHYSICAL target=%0d",target);
        drain(1,a0,n1);
        drain(2,a1,n2);
        repeat(2)@(negedge clk);
        if(protocol_fault)$fatal(1,"PAIR_FAULT target=%0d",target);
    endtask
    initial begin
        s_arid=0;s_araddr=0;s_arlen=0;s_arsize=4;s_arburst=1;
        s_arvalid=0;s_rready=0;
        repeat(5)@(negedge clk);rst=0;
        for(int n=1;n<=16;n++)begin
            automatic logic [31:0] a0=32'h8000_0100+32'((n%2)*16);
            automatic logic [31:0] a1=32'h8000_0800+32'(((n+1)%2)*16);
            run_pair(a0,n,a1,17-n);
        end
        run_pair(32'h8000_0ff0,1,32'h8000_1000,16);
        run_pair(32'h8000_0f00,16,32'h8000_1ff0,1);
        $display("HMIC_TWO_BANK_MULTIBEAT_PASS pairs=18 physical=%0d logical_beats=%0d cycles=%0d",
            phys_ars,logical_beats,cycles);
        $finish;
    end
endmodule
