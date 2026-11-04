// Original RV32 four-entry scheduling bank, October 2026.
// No state and no speculative readiness: current broadcasts are usable only
// when their actual completion is valid. All rank comparisons use pre-existing
// ages, not a candidate index selected by another readiness-dependent mux.
module rv32_issue_bank #(
    parameter FAST_WAKEUP=1
)(
    input wire [3:0] occupied,issue_allowed,
    input wire [15:0] ages,
    input wire [3:0] left_ready,right_ready,
    input wire [15:0] left_tags,right_tags,
    input wire [127:0] left_values,right_values,
    input wire [2:0] broadcast_valid,
    input wire [11:0] broadcast_tags,
    input wire [95:0] broadcast_values,
    output reg [3:0] eligible,
    output wire [2:0] occupancy_count,
    output wire first_valid,second_valid,
    output wire [1:0] first_slot,second_slot,
    output wire [3:0] first_age,second_age,
    output wire [31:0] first_left,first_right,second_left,second_right
);
    reg [31:0] ready_left[0:3],ready_right[0:3];
    reg [3:0] available_left,available_right,first_mask,second_mask;
    reg [3:0] older[0:3];
    integer i,j;
    always @* begin
        eligible=0;available_left=left_ready;available_right=right_ready;
        first_mask=0;second_mask=0;
        for(i=0;i<4;i=i+1)begin
            ready_left[i]=left_values[i*32+:32];
            ready_right[i]=right_values[i*32+:32];
            // Later channels retain the established deterministic priority.
            for(j=0;j<3;j=j+1)begin
                if(FAST_WAKEUP&&!left_ready[i]&&broadcast_valid[j]&&
                   broadcast_tags[j*4+:4]==left_tags[i*4+:4])begin
                    available_left[i]=1;ready_left[i]=broadcast_values[j*32+:32];
                end
                if(FAST_WAKEUP&&!right_ready[i]&&broadcast_valid[j]&&
                   broadcast_tags[j*4+:4]==right_tags[i*4+:4])begin
                    available_right[i]=1;ready_right[i]=broadcast_values[j*32+:32];
                end
            end
            eligible[i]=occupied[i]&&issue_allowed[i]&&available_left[i]&&available_right[i];
        end
        // Rank each eligible entry in parallel. Equal-age ties prefer the
        // lower local slot, matching the original ascending queue scan.
        for(i=0;i<4;i=i+1)begin
            for(j=0;j<4;j=j+1)begin
                older[i][j]=(i!=j)&&eligible[j]&&
                    ((ages[j*4+:4]<ages[i*4+:4])||
                     ((ages[j*4+:4]==ages[i*4+:4])&&(j<i)));
            end
            first_mask[i]=eligible[i]&&!(|older[i]);
            second_mask[i]=eligible[i]&&((older[i]==4'b0001)||(older[i]==4'b0010)||
                                        (older[i]==4'b0100)||(older[i]==4'b1000));
        end
    end
    assign occupancy_count={2'b0,occupied[0]}+{2'b0,occupied[1]}+
                           {2'b0,occupied[2]}+{2'b0,occupied[3]};
    assign first_valid=|first_mask;
    assign second_valid=|second_mask;
    assign first_slot={first_mask[2]|first_mask[3],first_mask[1]|first_mask[3]};
    assign second_slot={second_mask[2]|second_mask[3],second_mask[1]|second_mask[3]};
    assign first_age=({4{first_mask[0]}}&ages[3:0])|({4{first_mask[1]}}&ages[7:4])|
                     ({4{first_mask[2]}}&ages[11:8])|({4{first_mask[3]}}&ages[15:12]);
    assign second_age=({4{second_mask[0]}}&ages[3:0])|({4{second_mask[1]}}&ages[7:4])|
                      ({4{second_mask[2]}}&ages[11:8])|({4{second_mask[3]}}&ages[15:12]);
    assign first_left=({32{first_mask[0]}}&ready_left[0])|({32{first_mask[1]}}&ready_left[1])|
                      ({32{first_mask[2]}}&ready_left[2])|({32{first_mask[3]}}&ready_left[3]);
    assign first_right=({32{first_mask[0]}}&ready_right[0])|({32{first_mask[1]}}&ready_right[1])|
                       ({32{first_mask[2]}}&ready_right[2])|({32{first_mask[3]}}&ready_right[3]);
    assign second_left=({32{second_mask[0]}}&ready_left[0])|({32{second_mask[1]}}&ready_left[1])|
                       ({32{second_mask[2]}}&ready_left[2])|({32{second_mask[3]}}&ready_left[3]);
    assign second_right=({32{second_mask[0]}}&ready_right[0])|({32{second_mask[1]}}&ready_right[1])|
                        ({32{second_mask[2]}}&ready_right[2])|({32{second_mask[3]}}&ready_right[3]);
endmodule
