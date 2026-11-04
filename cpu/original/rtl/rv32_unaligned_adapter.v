// Original Soc-Core RAM misalignment adapter, November 2026.
// Aligned transfers are combinational pass-throughs. Misaligned half/word
// payloads are unshifted at u_wdata; results are normalized at u_rdata.
// Split stores are non-atomic. A bounded map failure is rejected before any
// subrequest; a later bus error can leave an earlier partial store visible.
module rv32_unaligned_adapter #(
    parameter ENABLE_DATA_RAM_GUARD=0,
    parameter [31:0] DATA_RAM_BASE=32'h00000000,
    parameter [31:0] DATA_RAM_LIMIT=32'hffffffff
)(
    input clk,reset,
    input u_valid,output u_ready,input [31:0] u_address,input u_write,
    input [31:0] u_wdata,input [3:0] u_wstrb,input [1:0] u_size,
    output u_rvalid,input u_rready,output [31:0] u_rdata,output u_error,
    output m_valid,input m_ready,output [31:0] m_address,output m_write,
    output [31:0] m_wdata,output [3:0] m_wstrb,output [1:0] m_size,
    input m_rvalid,output m_rready,input [31:0] m_rdata,input m_error
);
    localparam [2:0] IDLE=0,REQUEST0=1,WAIT0=2,REQUEST1=3,WAIT1=4,RESPONSE=5;
    reg [2:0] state;
    reg [31:0] address,first_data,result_data;
    reg [63:0] store_data;
    reg [7:0] store_mask;
    reg write_operation,second_needed,result_error;
    reg [1:0] byte_offset;
    wire misaligned=(u_size==2&&u_address[1:0]!=0)||(u_size==1&&u_address[0]);
    wire [32:0] last_address={1'b0,u_address}+(u_size==1?33'd1:33'd3);
    function peripheral;
        input [31:0] a;
        begin peripheral=a>=32'h30000000&&a<32'h84000000;end
    endfunction
    wire split_allowed=!last_address[32]&&!peripheral(u_address)&&!peripheral(last_address[31:0])&&
        (!ENABLE_DATA_RAM_GUARD||(u_address>=DATA_RAM_BASE&&last_address[31:0]<=DATA_RAM_LIMIT));
    wire idle=state==IDLE;
    wire first_request=state==REQUEST0;
    wire second_request=state==REQUEST1;
    wire first_transfer=m_rvalid&&(state==WAIT0||(first_request&&m_ready));
    wire second_transfer=m_rvalid&&(state==WAIT1||(second_request&&m_ready));
    wire [63:0] combined={m_rdata,first_data}>>{byte_offset,3'b0};
    assign u_ready=!reset&&idle&&m_ready;
    assign m_valid=!reset&&(idle?(u_valid&&!misaligned):(first_request||second_request));
    assign m_address=idle?u_address:(address+(second_request?32'd4:32'd0));
    assign m_write=idle?u_write:write_operation;
    assign m_wdata=idle?u_wdata:(second_request?store_data[63:32]:store_data[31:0]);
    assign m_wstrb=idle?u_wstrb:(second_request?store_mask[7:4]:store_mask[3:0]);
    assign m_size=idle?u_size:2'd2;
    assign u_rvalid=!reset&&(idle?m_rvalid:state==RESPONSE);
    assign u_rdata=idle?m_rdata:result_data;
    assign u_error=idle?m_error:result_error;
    assign m_rready=!reset&&(idle?u_rready:(first_request||state==WAIT0||second_request||state==WAIT1));
    always @(posedge clk)begin
        if(reset)begin
            state<=IDLE;address<=0;first_data<=0;result_data<=0;
            store_data<=0;store_mask<=0;write_operation<=0;
            second_needed<=0;result_error<=0;byte_offset<=0;
        end else begin
            case(state)
            IDLE:if(u_valid&&u_ready&&misaligned)begin
                address<={u_address[31:2],2'b0};byte_offset<=u_address[1:0];
                write_operation<=u_write;
                store_data<={32'b0,u_wdata}<<{u_address[1:0],3'b0};
                store_mask<={4'b0,u_wstrb}<<u_address[1:0];
                second_needed<=u_size==2||u_address[1:0]==3;
                result_error<=!split_allowed;result_data<=0;
                state<=split_allowed?REQUEST0:RESPONSE;
            end
            REQUEST0,WAIT0:begin
                if(first_request&&m_ready)state<=WAIT0;
                if(first_transfer)begin
                    first_data<=m_rdata;result_error<=m_error;
                    if(second_needed&&!m_error)state<=REQUEST1;
                    else begin result_data<=m_rdata>>{byte_offset,3'b0};state<=RESPONSE;end
                end
            end
            REQUEST1,WAIT1:begin
                if(second_request&&m_ready)state<=WAIT1;
                if(second_transfer)begin
                    result_data<=combined[31:0];result_error<=m_error;state<=RESPONSE;
                end
            end
            RESPONSE:if(u_rready)state<=IDLE;
            default:state<=IDLE;
            endcase
        end
    end
`ifdef VERILATOR
    reg held_request,held_response;
    reg [70:0] prior_request;
    reg [32:0] prior_response;
    always @(posedge clk)begin
        if(reset)begin held_request<=0;held_response<=0;end
        else begin
            if(held_request&&(!m_valid||{m_address,m_write,m_wdata,m_wstrb,m_size}!=prior_request))
                $fatal(1,"Unaligned adapter changed a held cache request");
            if(held_response&&(!u_rvalid||{u_error,u_rdata}!=prior_response))
                $fatal(1,"Unaligned adapter changed a held CPU response");
            held_request<=m_valid&&!m_ready;
            prior_request<={m_address,m_write,m_wdata,m_wstrb,m_size};
            held_response<=u_rvalid&&!u_rready;prior_response<={u_error,u_rdata};
        end
    end
`endif
endmodule
