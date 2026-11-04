`timescale 1ns/1ps
// PIPEOPT3: explicit bounded read bursts (1..16 beats), atomic error delivery.
// Native owner holds through rsp_last. Write packet: first LEN+1 beats on request
// channel, continuation LEN=0, one completion only after the actual AXI B.
module soc_rq_to_axi #(
    parameter int unsigned TIMEOUT_CYCLES=100_000_000,
    parameter bit BURST_ENABLE=1'b0
)(
    input logic clk,rst,ddr_ready,
    input logic req_valid,output logic req_ready,
    input logic req_write,input logic [31:0] req_addr,
    input logic [127:0] req_wdata,input logic [15:0] req_wstrb,
    input logic [3:0] req_id,
    input logic [3:0] req_len, // beats minus one; write continuations use LEN=0
    output logic rsp_valid,input logic rsp_ready,output logic rsp_last,
    output logic rsp_write,output logic [3:0] rsp_id,
    output logic [127:0] rsp_rdata,output logic rsp_error,
    output logic poisoned,
    output logic [3:0] m_awid,output logic [31:0] m_awaddr,
    output logic [7:0] m_awlen,output logic [2:0] m_awsize,
    output logic [1:0] m_awburst,output logic m_awvalid,input logic m_awready,
    output logic [127:0] m_wdata,output logic [15:0] m_wstrb,
    output logic m_wlast,m_wvalid,input logic m_wready,
    input logic [3:0] m_bid,input logic [1:0] m_bresp,
    input logic m_bvalid,output logic m_bready,
    output logic [3:0] m_arid,output logic [31:0] m_araddr,
    output logic [7:0] m_arlen,output logic [2:0] m_arsize,
    output logic [1:0] m_arburst,output logic m_arvalid,input logic m_arready,
    input logic [3:0] m_rid,input logic [127:0] m_rdata,
    input logic [1:0] m_rresp,input logic m_rlast,m_rvalid,
    output logic m_rready
);

 generate if (!BURST_ENABLE) begin: legacy
  assign rsp_last=1'b1;
  soc_rq_to_axi_single #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) reference_path(.*);
 end else begin: burst
  // No speculative address reads and no write completion fabrication.
  // Whole read burst is retired on AXI before any native beat is published.
  // An erroneous burst returns one terminal error; no partial input is used.
  typedef enum logic [3:0] {IDLE,AW,W,B,AR,R,LOAD,RESP,POISON,COLLECT} state_t;
  state_t state;
  logic [31:0] addr_q,wait_cycles;
  logic [127:0] wdata_q;
  logic [15:0] wstrb_q;
  logic [3:0] id_q,len_q,send_index;
  logic write_q,fault_q,poison_q;
  logic [8:0] received;
  logic [15:0] write_masks[0:15];
  logic [127:0] read_buffer[0:15]; // 256 logical bytes, no payload reset
  wire waiting=(state==AW||state==W||state==B||state==AR||state==R||state==COLLECT);
  wire step=(state==AW&&m_awready)||(state==W&&m_wready)||
      (state==B&&m_bvalid)||(state==AR&&m_arready)||(state==R&&m_rvalid)||(state==COLLECT&&req_valid);
  wire timeout_now=waiting&&!step&&(wait_cycles==TIMEOUT_CYCLES-1);
  wire read_bad=m_rresp!=0||m_rid!=id_q||(m_rlast!=(received=={5'd0,len_q}));
  wire terminal_bad=fault_q||read_bad;
  assign req_ready=!rst&&((state==IDLE&&ddr_ready&&!poison_q)||state==COLLECT);
  assign rsp_valid=state==RESP&&!rst;
  assign rsp_last=write_q||rsp_error||(send_index==len_q);
  assign poisoned=poison_q||state==POISON;
  assign m_awid=id_q;assign m_awaddr=addr_q;assign m_awlen={4'd0,len_q};
  assign m_awsize=3'd4;assign m_awburst=2'b01;assign m_awvalid=state==AW&&!rst;
  assign m_wdata=wdata_q;assign m_wstrb=wstrb_q;
  assign m_wlast=(send_index==len_q);assign m_wvalid=state==W&&!rst;
  assign m_bready=state==B&&!rst;
  assign m_arid=id_q;assign m_araddr=addr_q;assign m_arlen={4'd0,len_q};
  assign m_arsize=3'd4;assign m_arburst=2'b01;assign m_arvalid=state==AR&&!rst;
  assign m_rready=state==R&&!rst;
  always_ff @(posedge clk) begin
   if(rst)begin
    state<=IDLE;addr_q<=0;wait_cycles<=0;wdata_q<=0;wstrb_q<=0;
    id_q<=0;len_q<=0;send_index<=0;write_q<=0;fault_q<=0;poison_q<=0;received<=0;
    rsp_write<=0;rsp_id<=0;rsp_rdata<=0;rsp_error<=0;
   end else begin
    if(!waiting||step)wait_cycles<=0;
    else if(!timeout_now&&!poison_q)wait_cycles<=wait_cycles+1'b1;
    // Timeout is fail-closed: keep already asserted AR/AW/W stable and
    // drain eventual replies. Never release live ownership on a timer.
    if(timeout_now)begin poison_q<=1;fault_q<=1;end
    case(state)
     IDLE:if(req_valid&&req_ready)begin
      addr_q<=req_addr;wdata_q<=req_wdata;wstrb_q<=req_wstrb;id_q<=req_id;
      len_q<=req_len;write_q<=req_write;send_index<=0;received<=0;
      rsp_write<=req_write;rsp_id<=req_id;rsp_rdata<=0;rsp_error<=0;fault_q<=0;
      if(req_write)begin
       read_buffer[0]<=req_wdata;write_masks[0]<=req_wstrb;received<=1;
      end
      if(req_addr[3:0]!=0 || (req_write&&req_wstrb==0) ||
          ({1'b0,req_addr[11:0]}+(({9'd0,req_len}+13'd1)<<4)>13'd4096))begin
       fault_q<=1;
       // A multi-beat native write packet has already been accepted: consume
       // its remaining beats even when the header is illegal. No AXI issued.
       if(req_write&&req_len!=0)state<=COLLECT;
       else begin rsp_error<=1;state<=RESP;end
      end else state<=req_write?(req_len==0?AW:COLLECT):AR;
     end
     COLLECT:if(req_valid)begin
      read_buffer[received[3:0]]<=req_wdata;write_masks[received[3:0]]<=req_wstrb;
      received<=received+1'b1;
      if(!req_write||req_addr!=addr_q+(32'(received)<<4)||req_id!=id_q||req_len!=0||req_wstrb==0)begin
       fault_q<=1;poison_q<=1;
      end
      if(received=={5'd0,len_q})begin
       if(fault_q||!req_write||req_addr!=addr_q+(32'(received)<<4)||req_id!=id_q||req_len!=0||req_wstrb==0)begin
        rsp_error<=1;state<=RESP;
       end else state<=AW;
      end
     end
     AW:if(m_awready)state<=W;
     W:if(m_wready)begin
      if(send_index==len_q)state<=B;
      else begin
       send_index<=send_index+1'b1;wdata_q<=read_buffer[send_index+4'd1];
       wstrb_q<=write_masks[send_index+4'd1];
      end
     end
     B:if(m_bvalid)begin
      rsp_write<=1;rsp_id<=m_bid;rsp_error<=fault_q||m_bresp!=0||m_bid!=id_q;
      if(m_bid!=id_q)poison_q<=1;
      state<=RESP;
     end
     AR:if(m_arready)state<=R;
     R:if(m_rvalid)begin
      if(received<16)read_buffer[received[3:0]]<=m_rdata;
      if(received!=9'h1ff)received<=received+1'b1;
      if(read_bad)fault_q<=1;
      if(m_rid!=id_q || m_rlast!=(received=={5'd0,len_q}))poison_q<=1;
      if(m_rlast)begin
       rsp_error<=terminal_bad;rsp_write<=0;rsp_id<=id_q;send_index<=0;
       if(terminal_bad)begin rsp_rdata<=0;state<=RESP;end
       else if(len_q==0)begin rsp_rdata<=m_rdata;state<=RESP;end
       else state<=LOAD;
      end
     end
     LOAD:begin rsp_rdata<=read_buffer[0];state<=RESP;end
     RESP:if(rsp_ready)begin
      if(rsp_last)state<=poison_q?POISON:IDLE;
      else begin send_index<=send_index+1'b1;rsp_rdata<=read_buffer[send_index+4'd1];end
     end
     default:state<=POISON;
    endcase
   end
  end
 end endgenerate
endmodule

// One-outstanding 128-bit request adapter for the S3 Requant/LUT engine.
// This is an AXI master, not an AXI wire cast: AW/W/B and AR/R each retain
// their payload until handshake. A missing or wrongly tagged response poisons
// the port until the common board reset, so late DDR traffic cannot be reused.
module soc_rq_to_axi_single #(
    parameter int unsigned TIMEOUT_CYCLES=100_000_000
)(
    input logic clk,rst,ddr_ready,
    input logic req_valid,output logic req_ready,
    input logic req_write,input logic [31:0] req_addr,
    input logic [127:0] req_wdata,input logic [15:0] req_wstrb,
    input logic [3:0] req_id,
    output logic rsp_valid,input logic rsp_ready,
    output logic rsp_write,output logic [3:0] rsp_id,
    output logic [127:0] rsp_rdata,output logic rsp_error,
    output logic poisoned,
    output logic [3:0] m_awid,output logic [31:0] m_awaddr,
    output logic [7:0] m_awlen,output logic [2:0] m_awsize,
    output logic [1:0] m_awburst,output logic m_awvalid,input logic m_awready,
    output logic [127:0] m_wdata,output logic [15:0] m_wstrb,
    output logic m_wlast,m_wvalid,input logic m_wready,
    input logic [3:0] m_bid,input logic [1:0] m_bresp,
    input logic m_bvalid,output logic m_bready,
    output logic [3:0] m_arid,output logic [31:0] m_araddr,
    output logic [7:0] m_arlen,output logic [2:0] m_arsize,
    output logic [1:0] m_arburst,output logic m_arvalid,input logic m_arready,
    input logic [3:0] m_rid,input logic [127:0] m_rdata,
    input logic [1:0] m_rresp,input logic m_rlast,m_rvalid,
    output logic m_rready
);
    typedef enum logic [2:0] {IDLE,AW,W,B,AR,R,RESP,POISON} state_t;
    state_t state;
    logic [31:0] addr_q;
    logic [127:0] wdata_q;
    logic [15:0] wstrb_q;
    logic [3:0] id_q;
    logic write_q,poison_after_rsp;
    logic [31:0] wait_cycles;
    wire waiting=(state==AW || state==W || state==B || state==AR || state==R);
    wire step=(state==AW && m_awready) || (state==W && m_wready) ||
              (state==B && m_bvalid) || (state==AR && m_arready) ||
              (state==R && m_rvalid);
    assign req_ready=(state==IDLE) && ddr_ready && !rst;
    assign rsp_valid=(state==RESP);
    assign poisoned=(state==POISON) || poison_after_rsp;
    assign m_awid=id_q;assign m_awaddr=addr_q;assign m_awlen=0;
    assign m_awsize=3'd4;assign m_awburst=2'b01;assign m_awvalid=(state==AW);
    assign m_wdata=wdata_q;assign m_wstrb=wstrb_q;
    assign m_wlast=1'b1;assign m_wvalid=(state==W);
    assign m_bready=(state==B);
    assign m_arid=id_q;assign m_araddr=addr_q;assign m_arlen=0;
    assign m_arsize=3'd4;assign m_arburst=2'b01;assign m_arvalid=(state==AR);
    assign m_rready=(state==R);
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;addr_q<=0;wdata_q<=0;wstrb_q<=0;id_q<=0;
            write_q<=0;rsp_write<=0;rsp_id<=0;rsp_rdata<=0;rsp_error<=0;
            poison_after_rsp<=0;wait_cycles<=0;
        end else begin
            if(waiting) begin
                if(step) wait_cycles<=0;
                else if(wait_cycles==TIMEOUT_CYCLES-1) begin
                    rsp_write<=write_q;rsp_id<=id_q;rsp_rdata<=0;
                    rsp_error<=1;poison_after_rsp<=1;state<=RESP;
                end else wait_cycles<=wait_cycles+1'b1;
            end else wait_cycles<=0;
            case(state)
                IDLE: if(req_valid && req_ready) begin
                    addr_q<=req_addr;wdata_q<=req_wdata;wstrb_q<=req_wstrb;
                    id_q<=req_id;write_q<=req_write;
                    rsp_write<=req_write;rsp_id<=req_id;rsp_rdata<=0;
                    rsp_error<=0;poison_after_rsp<=0;
                    if(req_addr[3:0]!=0 || (req_write && req_wstrb==0)) begin
                        rsp_error<=1;state<=RESP;
                    end else state<=req_write?AW:AR;
                end
                AW: if(m_awready) state<=W;
                W: if(m_wready) state<=B;
                B: if(m_bvalid) begin
                    rsp_write<=1;rsp_id<=m_bid;rsp_error<=m_bresp!=0 || m_bid!=id_q;
                    if(m_bid!=id_q) poison_after_rsp<=1;
                    state<=RESP;
                end
                AR: if(m_arready) state<=R;
                R: if(m_rvalid) begin
                    rsp_write<=0;rsp_id<=m_rid;rsp_rdata<=m_rdata;
                    rsp_error<=m_rresp!=0 || m_rid!=id_q || !m_rlast;
                    if(m_rid!=id_q || !m_rlast) poison_after_rsp<=1;
                    state<=RESP;
                end
                RESP: if(rsp_ready) state<=poison_after_rsp?POISON:IDLE;
                default: state<=POISON;
            endcase
            // Timeout wins over a state transition only when no handshake.
            if(waiting && !step && wait_cycles==TIMEOUT_CYCLES-1)
                state<=RESP;
        end
    end
endmodule
