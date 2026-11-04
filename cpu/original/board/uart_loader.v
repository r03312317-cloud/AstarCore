// UART boot loader: receives a raw binary (64-byte padded) at 115200-8N1 from
// the board UART and writes it into the board SRAM via the writeback channel.
// CPU stays in reset until the host link goes idle or the image is complete.
// If no byte arrives within AUTOBOOT_CYCLES the CPU boots the BRAM-initialized
// image instead. After a UART load it sends "BOOT"+count32 before releasing.
module uart_loader #(
    parameter UART_DIV=1042,
    parameter [31:0] AUTOBOOT_CYCLES=32'd2400000000
)(
    input clk, reset,
    input uart_rx,
    output reg loading,
    output reg [31:0] loaded_bytes,
    output reg w_req, input w_gnt,
    output reg [31:0] w_addr, output reg [63:0] w_data,
    output reg w_last, output w_id,
    input b_valid, input b_error,
    output reg tx, output reg tx_busy,
    // read-back verify channel (board-memory data port, used while loading)
    output reg d_req, input d_gnt, output reg [31:0] d_addr,
    input d_valid, input [63:0] d_data, input d_error
);
    assign w_id=1'b0;
    localparam [23:0] GAP_CYCLES=24'd10066330; // ~84 ms idle ends the load

    // ---- UART RX ----
    reg [1:0] rx_sync;
    always @(posedge clk) rx_sync<={rx_sync[0],uart_rx};
    wire rx=rx_sync[1];
    reg [10:0] rx_baud; reg [3:0] rx_bit; reg [7:0] rx_byte;
    reg rx_active; reg rx_valid;
    always @(posedge clk) begin
        if(reset) begin rx_baud<=0; rx_bit<=0; rx_active<=0; rx_valid<=0; rx_byte<=0; end
        else begin
            rx_valid<=0;
            if(!rx_active) begin
                if(!rx) begin rx_active<=1; rx_baud<=(UART_DIV>>1); rx_bit<=0; end
            end else if(rx_baud==UART_DIV-1) begin
                rx_baud<=0;
                if(rx_bit==0) begin
                    if(rx) rx_active<=0;          // false start
                    else rx_bit<=1;
                end else if(rx_bit<=8) begin
                    rx_byte<={rx,rx_byte[7:1]}; rx_bit<=rx_bit+1'b1;
                end else begin
                    rx_active<=0;
                    if(rx) rx_valid<=1;           // stop bit present
                end
            end else rx_baud<=rx_baud+1'b1;
        end
    end

    // ---- control + write channel + TX message (single process) ----
    localparam L_WAIT=0,L_RX=1,L_WRITE=2,L_MSG=3,L_DONE=4,
               L_VREQ=5,L_VRECV=6,L_VMSG=7;
    reg [12:0] v_line; reg [2:0] v_beat; reg [63:0] checksum;
    reg [2:0] st;
    reg [2:0] byte_idx, beat_idx;
    reg [63:0] beat_shift;
    reg [31:0] wait_count; reg [23:0] gap_count;
    // TX serializer
    reg [10:0] tx_baud; reg [3:0] tx_bit; reg [7:0] tx_cur; reg tx_send;
    reg [4:0] msg_idx;

    // message: "BOOT" count32 | "VRFY" checksum64  (20 bytes)
    wire [4:0] mi=msg_idx;
    wire [7:0] msg_byte =
        (mi==0)?8'h42:(mi==1)?8'h4F:(mi==2)?8'h4F:(mi==3)?8'h54:
        (mi==4)?loaded_bytes[7:0]:(mi==5)?loaded_bytes[15:8]:
        (mi==6)?loaded_bytes[23:16]:(mi==7)?loaded_bytes[31:24]:
        (mi==8)?8'h56:(mi==9)?8'h52:(mi==10)?8'h46:(mi==11)?8'h59:
        checksum[8*(mi-12) +: 8];

    always @(posedge clk) begin
        if(reset) begin
            st<=L_WAIT; loading<=1; loaded_bytes<=0;
            byte_idx<=0; beat_idx<=0; beat_shift<=0;
            w_req<=0; w_last<=0; w_addr<=32'h10000000; w_data<=0;
            wait_count<=0; gap_count<=0;
            tx<=1; tx_busy<=0; tx_send<=0; tx_baud<=0; tx_bit<=0; tx_cur<=0; msg_idx<=0;
            d_req<=0; d_addr<=32'h10000000; v_line<=0; v_beat<=0; checksum<=0;
        end else begin
            case(st)
                L_WAIT: begin
                    if(rx_valid) begin
                        st<=L_RX; loaded_bytes<=1;
                        beat_shift<={rx_byte,56'd0}; byte_idx<=1;
                        wait_count<=0; gap_count<=0;
                    end else if(wait_count==AUTOBOOT_CYCLES) begin
                        loading<=0; st<=L_DONE;
                    end else wait_count<=wait_count+1'b1;
                end
                L_RX: begin
                    if(rx_valid) begin
                        gap_count<=0;
                        loaded_bytes<=loaded_bytes+1'b1;
                        if(byte_idx==7) begin
                            w_data<={rx_byte,beat_shift[63:8]};
                            w_req<=1; w_last<=(beat_idx==7);
                            st<=L_WRITE;
                        end else begin
                            beat_shift<={rx_byte,beat_shift[63:8]};
                            byte_idx<=byte_idx+1'b1;
                        end
                    end else if(gap_count==GAP_CYCLES) begin
                        st<=L_MSG; msg_idx<=0; tx_busy<=1;
                    end else gap_count<=gap_count+1'b1;
                end
                L_WRITE: begin
                    if(w_req && w_gnt) begin
                        w_req<=0; w_last<=0;
                        if(beat_idx==7) begin
                            beat_idx<=0; w_addr<=w_addr+32'd64;
                        end else beat_idx<=beat_idx+1'b1;
                        st<=L_RX; byte_idx<=0;
                    end
                end
                L_MSG: begin
                    if(!tx_send) begin
                        if(msg_idx==8) begin
                            // BOOT message done; verify what landed in SRAM.
                            st<=L_VREQ; v_line<=0; checksum<=0;
                            d_addr<=32'h10000000;
                        end
                        else begin
                            tx_send<=1; tx_cur<=msg_byte;
                            tx_bit<=0; tx_baud<=0; tx<=0;   // start bit now
                        end
                    end else if(tx_baud==UART_DIV-1) begin
                        tx_baud<=0;
                        if(tx_bit<8) begin tx<=tx_cur[tx_bit]; tx_bit<=tx_bit+1'b1; end
                        else if(tx_bit==8) begin tx<=1; tx_bit<=9; end
                        else begin tx_send<=0; msg_idx<=msg_idx+1'b1; end
                    end else tx_baud<=tx_baud+1'b1;
                end
                L_VREQ: begin
                    if(loaded_bytes==0) begin st<=L_DONE; loading<=0; end
                    else if(!d_req) d_req<=1;
                    else if(d_gnt) begin d_req<=0; v_beat<=0; st<=L_VRECV; end
                end
                L_VRECV: begin
                    if(d_valid) begin
                        checksum<=checksum^d_data;
                        if(v_beat==7) begin
                            if(d_addr==32'h10000000+{loaded_bytes[31:6],6'b0}-32'd64)
                                begin st<=L_VMSG; msg_idx<=8; end
                            else begin d_addr<=d_addr+32'd64; st<=L_VREQ; end
                        end else v_beat<=v_beat+1'b1;
                    end
                end
                L_VMSG: begin
                    if(!tx_send) begin
                        if(msg_idx==20) begin tx_busy<=0; loading<=0; st<=L_DONE; end
                        else begin
                            tx_send<=1; tx_cur<=msg_byte;
                            tx_bit<=0; tx_baud<=0; tx<=0;
                        end
                    end else if(tx_baud==UART_DIV-1) begin
                        tx_baud<=0;
                        if(tx_bit<8) begin tx<=tx_cur[tx_bit]; tx_bit<=tx_bit+1'b1; end
                        else if(tx_bit==8) begin tx<=1; tx_bit<=9; end
                        else begin tx_send<=0; msg_idx<=msg_idx+1'b1; end
                    end else tx_baud<=tx_baud+1'b1;
                end
                default: begin loading<=0; st<=L_DONE; end
            endcase
        end
    end
endmodule
