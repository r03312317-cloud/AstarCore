// Board demo's 1280x720 RGB565 register table and SCCB sequencer, with a
// power-up reset delay referenced to the 27 MHz system oscillator. The vendor
// SCCB controller does not inspect ACK or sensor ID; cfg_done means the table
// was sent, not that an OV5640 was physically detected.
module soc_ov5640_config(
    input logic clk_27m,rst_n,
    output logic SCL,SDA,cam_rst_n,init_done
);
    timeunit 1ns;timeprecision 1ps;
    logic [20:0] power_count;
    logic config_release,cfg_start,cfg_end;
    logic [23:0] cfg_data;
    always_ff @(posedge clk_27m or negedge rst_n)begin
        if(!rst_n)power_count<=0;
        else if(power_count<21'd1_500_000)power_count<=power_count+1'b1;
    end
    assign cam_rst_n=rst_n && power_count>=21'd400_000;
    assign config_release=rst_n && power_count==21'd1_500_000;
    data_init #(.REG_NUM(8'd248)) u_register_table(
        .sys_clk(clk_27m),.sys_rst_n(config_release),.cfg_end,
        .cfg_start,.cfg_data,.cfg_done(init_done));
    SCCB #(.SYS_CLK(27_000_000),.SCCB_CLK(250_000)) bus(
        .clk(clk_27m),.rst_n(config_release),.sccb_start(cfg_start),
        .data_in(cfg_data),.SCL,.SDA,.sccb_done(cfg_end));
endmodule
