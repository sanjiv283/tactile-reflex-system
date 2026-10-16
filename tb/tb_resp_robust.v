`timescale 1ns / 1ps
// Robustness of upload_resp_tx + uart_tx beyond the default FIFO depth of 4 (which tb_upload_resp_tx covers):
//   * any supported DEPTH (>= 2, power of two or not): capacity DEPTH+1 from an empty queue, order, lost-flag rules,
//     read/write pointer wrap-around over many fills (-P DEPTH_P=...);
//   * a reset asserted at EVERY phase of a response frame (every 7th clock across more than one whole frame, so the
//     SOF, STATUS, INFO and CHK bytes and the byte hand-over clocks are all hit): the line is idle high at once,
//     the queue and the pending lost flag are gone, at most the frame already complete on the wire is still
//     delivered, and the next response is clean and parses.
// Clock 1 MHz, 62500 baud (16 clocks/bit, 640 clocks per frame): only to keep the bench short.
module tb_resp_robust;
    parameter DEPTH_P = 4;
    localparam CLK_HZ = 1_000_000, BAUD = 62_500;
    localparam real T = 1000.0, BIT = 16000.0;
    localparam FRAME_CLKS = 640;

    reg clk = 0;
    always #(T/2.0) clk = ~clk;

    reg        rst = 1, ev_ack = 0, ev_nak = 0, ev_commit = 0;
    reg  [3:0] ev_err = 0;
    reg  [6:0] ev_entries = 0;
    wire [7:0] tx_data;
    wire       tx_valid, tx_ready, tx, tx_busy, overflow, resp_busy;

    upload_resp_tx #(.DEPTH(DEPTH_P)) dut (
        .clk(clk), .rst(rst), .ev_ack(ev_ack), .ev_nak(ev_nak), .ev_commit(ev_commit),
        .ev_err(ev_err), .ev_entries(ev_entries),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready), .overflow(overflow), .busy(resp_busy));
    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst(rst), .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready), .tx(tx), .busy(tx_busy));

    wire [7:0] mdata; wire mvalid; wire [31:0] mn, mfe;
    uart_monitor #(.BIT_NS(BIT)) mon (.rx(tx), .data(mdata), .valid(mvalid), .n_bytes(mn), .n_fe(mfe));

    integer errors = 0;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask
    task ticks(input integer n); repeat (n) @(posedge clk); endtask

    // ---- host parser (the documented algorithm)
    reg [1:0] pst = 0;
    reg [7:0] p_st, p_info;
    integer n_good = 0, n_bad = 0, n_resync = 0;
    reg [7:0] f_st [0:1023]; reg [7:0] f_info [0:1023];
    function frame_ok(input [7:0] st, input [7:0] info);
        reg [7:0] b;
        begin
            b = st & 8'h7F;
            frame_ok = (b == 8'h06 && info <= 64) || (b == 8'h07 && info == 64) || (b == 8'h15 && info >= 1 && info <= 10);
        end
    endfunction
    always @(posedge mvalid) begin : parser
        reg [7:0] b;
        b = mdata;
        case (pst)
            2'd0: if (b == 8'h5A) pst = 1;
            2'd1: if (b == 8'h5A) begin n_resync = n_resync + 1; pst = 1; end else begin p_st = b; pst = 2; end
            2'd2: if (b == 8'h5A) begin n_resync = n_resync + 1; pst = 1; end else begin p_info = b; pst = 3; end
            2'd3: if (b == 8'h5A) begin n_resync = n_resync + 1; pst = 1; end
                  else begin
                      if (b == (p_st ^ p_info) && frame_ok(p_st, p_info)) begin
                          f_st[n_good % 1024] = p_st; f_info[n_good % 1024] = p_info; n_good = n_good + 1;
                      end else n_bad = n_bad + 1;
                      pst = 0;
                  end
        endcase
    end

    // test ids are carried in INFO, which is at most 64 for an ACK: wrap them into 1..60
    function integer idf(input integer x); idf = ((x - 1) % 60) + 1; endfunction
    task burst(input integer n, input integer first);
        integer k;
        begin
            @(negedge clk);
            for (k = 0; k < n; k = k + 1) begin ev_ack = 1; ev_entries = idf(first + k); @(negedge clk); end
            ev_ack = 0;
        end
    endtask
    task one(input integer id); begin @(negedge clk); ev_ack = 1; ev_entries = id; @(negedge clk); ev_ack = 0; end endtask
    task drain; begin ticks(4); while (resp_busy || tx_busy) ticks(1); ticks(2 * FRAME_CLKS); end endtask
    task do_reset; begin @(negedge clk); rst = 1; ticks(3); @(negedge clk); rst = 0; ticks(4); end endtask

    integer g0, i, k, ok, off, extra, bad_idle, bad_cnt, bad_last, bad_flush, iter;
    integer cap;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_resp_robust);
        cap = DEPTH_P + 1;
        $display("INFO  DEPTH=%0d -> capacity from an empty queue = %0d responses", DEPTH_P, cap);
        ticks(6); @(negedge clk); rst = 0; ticks(4);

        // ---- exactly full: DEPTH+1 events in consecutive clocks are all delivered, nothing flagged, no overflow
        g0 = n_good; burst(cap, 1); drain;
        ok = (n_good == g0 + cap) && !overflow;
        for (i = 0; i < cap; i = i + 1) if (!(f_st[(g0+i)%1024] === 8'h06 && f_info[(g0+i)%1024] === idf(i + 1))) ok = 0;
        check(ok, "DEPTH+1 events in consecutive clocks: all delivered in order, no lost flag, overflow stays 0");

        // ---- one more than capacity: exactly one dropped, next response flagged, following one clean
        g0 = n_good; burst(cap + 1, 11); drain;
        check(n_good == g0 + cap && overflow, "DEPTH+2 events: only DEPTH+1 delivered, overflow set");
        ok = 1; for (i = 0; i < cap; i = i + 1) if (!(f_st[(g0+i)%1024] === 8'h06 && f_info[(g0+i)%1024] === idf(11 + i))) ok = 0;
        check(ok, "the delivered ones are the first DEPTH+1, in order, unflagged");
        g0 = n_good; one(40); drain;
        check(n_good == g0 + 1 && f_st[g0 % 1024] === 8'h86 && f_info[g0 % 1024] === 8'd40, "next response after the drop carries the lost flag (0x86)");
        g0 = n_good; one(41); drain;
        check(f_st[g0 % 1024] === 8'h06 && f_info[g0 % 1024] === 8'd41, "following response is clean again");

        // ---- many fills: pointers wrap repeatedly, order and content stay right
        do_reset; ok = 1; g0 = n_good;
        for (k = 0; k < 8; k = k + 1) begin burst(cap, 1 + k * cap); drain; end
        if (n_good != g0 + 8 * cap) ok = 0;
        for (i = 0; i < 8 * cap; i = i + 1) if (!(f_st[(g0+i)%1024] === 8'h06 && f_info[(g0+i)%1024] === idf(i + 1))) ok = 0;
        check(ok && !overflow, "8 consecutive full fills (pointer wrap-around 8 times): every response intact and in order");
        g0 = n_good; ok = 1;
        for (k = 0; k < 3 * DEPTH_P + 2; k = k + 1) begin one(k + 1); ticks(2 * FRAME_CLKS); end
        if (n_good != g0 + 3 * DEPTH_P + 2) ok = 0;
        for (i = 0; i < 3 * DEPTH_P + 2; i = i + 1) if (!(f_info[(g0+i)%1024] === idf(i + 1))) ok = 0;
        check(ok, "single events one at a time, 3*DEPTH+2 of them: pointers wrap, all delivered in order");
        check(n_bad == 0, "no malformed frame on the wire in the whole capacity/wrap section");

        // ---- reset at every phase of the frame
        bad_idle = 0; bad_cnt = 0; bad_last = 0; bad_flush = 0; iter = 0; extra = 0;
        for (off = 0; off <= FRAME_CLKS + 70; off = off + 7) begin
            do_reset; drain;
            iter = iter + 1;
            // alternate: plain queue, or queue plus pending lost flag (burst larger than capacity)
            if (iter % 2) burst(3, 51); else burst(cap + 2, 51);
            ticks(off);
            g0 = n_good;
            @(negedge clk); rst = 1;
            @(negedge clk);                                    // one clock after reset was applied
            if (tx !== 1'b1 || tx_busy !== 1'b0 || resp_busy !== 1'b0) bad_idle = bad_idle + 1;
            ticks(2); @(negedge clk); rst = 0;
            ticks(3 * FRAME_CLKS);                             // anything not flushed would be sent by now
            if (tx !== 1'b1) bad_idle = bad_idle + 1;
            k = n_good - g0;                                   // frames completed after the reset was applied
            if (k > 1) bad_flush = bad_flush + 1;              // at most the frame already complete on the wire
            if (k == 1 && !(f_info[g0 % 1024] >= 51 && f_info[g0 % 1024] <= 60)) bad_flush = bad_flush + 1;
            if (overflow) bad_flush = bad_flush + 1;           // reset clears the sticky overflow flag
            g0 = n_good; one(33); drain;
            if (!(n_good == g0 + 1 && f_st[g0 % 1024] === 8'h06 && f_info[g0 % 1024] === 8'd33)) bad_last = bad_last + 1;
            if (k == 1) extra = extra + 1;
        end
        $display("INFO  %0d reset positions swept; %0d of them still completed one frame already fully on the wire", iter, extra);
        check(bad_idle == 0, "every reset phase: TX idle high one clock after reset, queue empty, transmitter idle");
        check(bad_flush == 0, "every reset phase: queued frames are not sent after reset (at most the frame already complete), overflow cleared");
        check(bad_last == 0, "every reset phase: the first response after reset is a single clean frame, no stale lost flag (0x06, not 0x86)");
        check(n_good > 0, "parser decoded valid frames (resynchronised after the truncated ones)");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #3_000_000_000; $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
