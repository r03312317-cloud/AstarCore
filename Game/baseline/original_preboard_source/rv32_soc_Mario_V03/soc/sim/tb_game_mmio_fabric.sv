`timescale 1ns/1ps
module tb_game_mmio_fabric;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst, req_valid, req_ready, req_write, req_is_fetch;
    logic [31:0] req_addr, req_wdata;
    logic [3:0] req_wstrb;
    logic rsp_valid, rsp_ready, rsp_error;
    logic [31:0] rsp_rdata;
    logic [1:0] m_req_valid, m_req_ready, m_rsp_valid, m_rsp_ready, m_rsp_error;
    logic [31:0] m_req_addr, m_req_wdata;
    logic m_req_write;
    logic [3:0] m_req_wstrb;
    logic [1:0][31:0] m_rsp_rdata;

    game_mmio_fabric dut (.*);
    task automatic tick; @(posedge clk); #1; endtask
    task automatic check(input logic condition, input string reason);
        if (!condition) $fatal(1, "%s", reason);
    endtask

    initial begin
        rst = 1; req_valid = 0; req_addr = 0; req_write = 0; req_wdata = 0;
        req_is_fetch = 0; req_wstrb = 4'hf; rsp_ready = 0;
        m_req_ready = 2'b11; m_rsp_valid = 0; m_rsp_error = 0;
        m_rsp_rdata[0] = 32'h11223344; m_rsp_rdata[1] = 32'h55667788;
        repeat (2) tick();
        rst = 0;

        // Video accepts a request, then takes multiple cycles to respond.
        req_addr = 32'h60001108; req_write = 1; req_valid = 1; #1;
        check(req_ready && m_req_valid == 2'b10, "video request routing");
        tick();
        req_valid = 0; req_addr = 32'h60001f00; m_rsp_valid = 2'b01; rsp_ready = 1; #1;
        repeat (6) begin
            check(!rsp_valid && !req_ready && m_rsp_ready == 2'b10,
                  "fabric responded before the selected slave");
            tick();
        end
        m_rsp_valid = 2'b10; rsp_ready = 0; #1;
        check(rsp_valid && !rsp_error && rsp_rdata == 32'h55667788 && m_rsp_ready == 0,
              "video response must be held under backpressure");
        repeat (3) tick();
        check(rsp_valid && rsp_rdata == 32'h55667788, "response changed while stalled");
        rsp_ready = 1; #1;
        check(m_rsp_ready == 2'b10, "ready sent to wrong video response");
        tick(); m_rsp_valid = 0; #1;
        check(!rsp_valid && req_ready, "video response did not retire");

        // Input response must retain owner 0 even if the request bus changes.
        req_addr = 32'h60001004; req_write = 0; req_valid = 1; #1;
        check(m_req_valid == 2'b01 && req_ready, "input request routing");
        tick(); req_valid = 0; req_addr = 32'h60001100; m_rsp_valid = 2'b01; #1;
        check(rsp_valid && rsp_rdata == 32'h11223344 && m_rsp_ready == 2'b01,
              "input response owner was not retained");
        tick(); m_rsp_valid = 0; #1;

        // Invalid pages and fetches receive a latched local error, independent
        // of later changes on the request bus and any slave responses.
        req_addr = 32'h60001244; req_valid = 1; rsp_ready = 0; #1;
        check(req_ready && m_req_valid == 0, "invalid page forwarded");
        tick(); req_valid = 0; req_addr = 32'h60001000; #1;
        check(rsp_valid && rsp_error && rsp_rdata == 32'h0bad0002 && m_rsp_ready == 0,
              "invalid-page response not held");
        repeat (2) tick();
        rsp_ready = 1; tick(); #1;
        req_addr = 32'h60001100; req_is_fetch = 1; req_valid = 1; #1;
        check(req_ready && m_req_valid == 0, "instruction fetch forwarded");
        tick(); req_valid = 0; req_is_fetch = 0; req_addr = 32'h60001000; #1;
        check(rsp_valid && rsp_error, "fetch error not retained");
        tick(); #1;
        check(!rsp_valid && req_ready, "fetch error did not retire");
        $display("PASS: delayed responses, owner retention, backpressure, local errors");
        $finish;
    end
endmodule
