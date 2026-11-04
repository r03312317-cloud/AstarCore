// Fixed image transforms sharing one AXI port. Completion is a DDR fence:
// the core has finished AND the adapter has received every write response.
module soc_image_accel(
    input logic clk,rst,ddr_ready,external_poisoned,
    input logic req_valid,output logic req_ready,
    input logic [15:0] req_addr,input logic req_write,
    input logic [31:0] req_wdata,input logic [3:0] req_wstrb,
    output logic rsp_valid,input logic rsp_ready,
    output logic [31:0] rsp_rdata,output logic rsp_error,
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
    logic start,mode,lut_we;
    logic [29:0] src_base,dst_base;
    logic [7:0] lut_idx,lut_dat;
    logic busy,finish_seen,done,adapter_idle,drained,poisoned;
    logic [7:0] errors;
    logic [31:0] cycles,read_beats,write_beats;
    wire failed=(|errors)||poisoned||external_poisoned;
    logic [1:0] cbusy,cdone,rd_valid,rd_ready,rspv,rspr,wr_valid,wr_ready;
    logic [1:0][29:0] rd_addr,wr_addr;
    logic [1:0][127:0] rspd,wr_data;
    logic [1:0][31:0] reads,writes;
    assign read_beats=reads[mode];
    assign write_beats=writes[mode];
    soc_image_mmio_mem registers(
        .clk,.rst,.ddr_ready,.axi_poisoned(poisoned||external_poisoned),
        .req_valid,.req_ready,.req_addr,.req_write,.req_wdata,.req_wstrb,
        .rsp_valid,.rsp_ready,.rsp_rdata,.rsp_error,
        .start,.mode,.src_base,.dst_base,.lut_we,.lut_idx,.lut_dat,
        .engine_busy(busy||start),.engine_done(done),.engine_error((busy||done)&&failed),
        .active_cycles(cycles),.read_beats,.write_beats);
    always_ff @(posedge clk)begin
        done<=0;
        if(rst)begin busy<=0;finish_seen<=0;done<=0;cycles<=0;end
        else begin
            if(start)begin busy<=1;finish_seen<=0;cycles<=0;end
            else if(busy)begin
                if(cycles!=32'hffffffff)cycles<=cycles+1'b1;
                if(cdone[mode])finish_seen<=1;
                if(finish_seen&&drained)begin busy<=0;done<=1;end
            end
        end
    end
    soc_preprocess320_core preprocess(
        .clk,.rst,.start(start&&!mode),.src_base,.dst_base,.busy(cbusy[0]),.done(cdone[0]),
        .lut_we,.lut_idx,.lut_dat,
        .rd_valid(rd_valid[0]),.rd_ready(rd_ready[0]),.rd_addr(rd_addr[0]),
        .rsp_valid(rspv[0]),.rsp_ready(rspr[0]),.rsp_data(rspd[0]),
        .wr_valid(wr_valid[0]),.wr_ready(wr_ready[0]),.wr_addr(wr_addr[0]),.wr_data(wr_data[0]),
        .stat_rd_beats(reads[0]),.stat_wr_beats(writes[0]));
    soc_display_resize_core resize(
        .clk,.rst,.start(start&&mode),.src_base,.dst_base,.busy(cbusy[1]),.done(cdone[1]),
        .rd_valid(rd_valid[1]),.rd_ready(rd_ready[1]),.rd_addr(rd_addr[1]),
        .rsp_valid(rspv[1]),.rsp_ready(rspr[1]),.rsp_data(rspd[1]),
        .wr_valid(wr_valid[1]),.wr_ready(wr_ready[1]),.wr_addr(wr_addr[1]),.wr_data(wr_data[1]),
        .stat_rd_beats(reads[1]),.stat_wr_beats(writes[1]));
    logic core_rdready,core_rspvalid,core_wrready;
    logic [127:0] core_rspdata;
    assign rd_ready=mode?{core_rdready,1'b0}:{1'b0,core_rdready};
    assign rspv=mode?{core_rspvalid,1'b0}:{1'b0,core_rspvalid};
    assign wr_ready=mode?{core_wrready,1'b0}:{1'b0,core_wrready};
    assign rspd={core_rspdata,core_rspdata};
    soc_image_axi_adapter adapter(
        .clk,.rst,.frame_start(start),.frame_finish(cdone[mode]),
        .rd_valid(rd_valid[mode]),.rd_ready(core_rdready),.rd_addr(rd_addr[mode]),
        .rsp_valid(core_rspvalid),.rsp_ready(rspr[mode]),.rsp_data(core_rspdata),
        .wr_valid(wr_valid[mode]),.wr_ready(core_wrready),.wr_addr(wr_addr[mode]),.wr_data(wr_data[mode]),
        .idle(adapter_idle),.drained,.error_sticky(errors),.poisoned,
        .m_awid,
        .m_awaddr,
        .m_awlen,
        .m_awsize,
        .m_awburst,
        .m_awvalid,
        .m_awready,
        .m_wdata,
        .m_wstrb,
        .m_wlast,
        .m_wvalid,
        .m_wready,
        .m_bid,
        .m_bresp,
        .m_bvalid,
        .m_bready,
        .m_arid,
        .m_araddr,
        .m_arlen,
        .m_arsize,
        .m_arburst,
        .m_arvalid,
        .m_arready,
        .m_rid,
        .m_rdata,
        .m_rresp,
        .m_rlast,
        .m_rvalid,
        .m_rready);
endmodule
