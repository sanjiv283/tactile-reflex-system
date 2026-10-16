`timescale 1ns / 1ps
// Self-checking testbench: upload_resp_tx + uart_tx, events injected as lut_upload_ctrl would.
// The serial line is decoded by tb/uart_monitor.v and parsed by the HOST PARSER below, which is the
// algorithm documented in upload_resp_tx.v / README. Clock 1 MHz, 62500 baud (16 clocks/bit),
// FIFO depth 4: only to keep simulation short; the logic is clock-count based.
module tb_upload_resp_tx;
    localparam CLK_HZ = 1_000_000, BAUD = 62_500, DEPTH = 4;
    localparam real T = 1000.0, BIT = 16000.0;            // exact: 1 MHz clock, 16 clocks/bit
    localparam FRAME_CLKS = 4 * 10 * 16;                  // 640 clocks per response frame

    reg clk = 0;
    always #(T/2.0) clk = ~clk;

    reg        rst = 1;
    reg        ev_ack = 0, ev_nak = 0, ev_commit = 0;
    reg  [3:0] ev_err = 0;
    reg  [6:0] ev_entries = 0;
    wire [7:0] tx_data;
    wire       tx_valid, tx_ready, tx, tx_busy, overflow, resp_busy;

    upload_resp_tx #(.DEPTH(DEPTH)) dut (
        .clk(clk), .rst(rst), .ev_ack(ev_ack), .ev_nak(ev_nak), .ev_commit(ev_commit),
        .ev_err(ev_err), .ev_entries(ev_entries),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready),
        .overflow(overflow), .busy(resp_busy));
    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst(rst), .tx_data(tx_data), .tx_valid(tx_valid),
        .tx_ready(tx_ready), .tx(tx), .busy(tx_busy));

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

    // ---------------- raw byte log (every byte seen on the wire) with start times
    reg [7:0] raw [0:1023]; real bt [0:1023]; integer nraw = 0;
    always @(posedge mvalid) begin raw[nraw % 1024] = mdata; bt[nraw % 1024] = mon.t_start; nraw = nraw + 1; end

    // ---------------- HOST PARSER (documented algorithm)
    reg [1:0] pst = 0;
    reg [7:0] p_st, p_info;
    integer n_good = 0, n_bad = 0, n_resync = 0;
    reg [7:0] f_st [0:511]; reg [7:0] f_info [0:511];
    function frame_ok(input [7:0] st, input [7:0] info);
        reg [7:0] b;
        begin
            b = st & 8'h7F;
            frame_ok = (b == 8'h06 && info <= 64) || (b == 8'h07 && info == 64) ||
                       (b == 8'h15 && info >= 1 && info <= 10);
        end
    endfunction
    task pfeed(input [7:0] b);
        begin
            case (pst)
                2'd0: if (b == 8'h5A) pst = 1;
                2'd1: if (b == 8'h5A) begin n_resync = n_resync + 1; pst = 1; end
                      else begin p_st = b; pst = 2; end
                2'd2: if (b == 8'h5A) begin n_resync = n_resync + 1; pst = 1; end
                      else begin p_info = b; pst = 3; end
                2'd3: begin
                    if (b == 8'h5A) begin n_resync = n_resync + 1; pst = 1; end
                    else begin
                        if (b == (p_st ^ p_info) && frame_ok(p_st, p_info)) begin
                            f_st[n_good % 512] = p_st; f_info[n_good % 512] = p_info; n_good = n_good + 1;
                        end else n_bad = n_bad + 1;
                        pst = 0;
                    end
                end
            endcase
        end
    endtask
    always @(posedge mvalid) pfeed(mdata);

    // ---------------- event drivers (one clock wide, applied on the falling edge)
    task ev_ack_p(input [6:0] entries);
        begin @(negedge clk); ev_ack = 1; ev_commit = 0; ev_entries = entries; @(negedge clk); ev_ack = 0; end
    endtask
    task ev_commit_p;
        begin @(negedge clk); ev_ack = 1; ev_commit = 1; ev_entries = 7'd64; @(negedge clk); ev_ack = 0; ev_commit = 0; end
    endtask
    task ev_nak_p(input [3:0] code);
        begin @(negedge clk); ev_nak = 1; ev_err = code; @(negedge clk); ev_nak = 0; end
    endtask
    // n consecutive one-clock ACK events on consecutive clocks, ids first, first+1, ...
    task burst(input integer n, input integer first);
        integer k;
        begin
            @(negedge clk);
            for (k = 0; k < n; k = k + 1) begin ev_ack = 1; ev_entries = first + k; @(negedge clk); end
            ev_ack = 0;
        end
    endtask
    task wait_idle;                       // everything sent and the line idle for 3 frame times
        begin ticks(4); while (resp_busy || tx_busy) ticks(1); ticks(3 * FRAME_CLKS); end
    endtask

    // expected-frame checks against the parser's accepted frames (index relative to snapshot g0)
    integer g0, r0;
    task snap; begin g0 = n_good; r0 = nraw; end endtask
    task exp_f(input integer k, input [7:0] base, input [6:0] info, input lost, input [8*96-1:0] name);
        begin
            check(f_st[(g0 + k) % 512] === (base | (lost ? 8'h80 : 8'h00)) && f_info[(g0 + k) % 512] === {1'b0, info}, name);
        end
    endtask
    function [7:0] spec_chk(input [7:0] st, input [7:0] info); spec_chk = st ^ info; endfunction

    integer i, k, ok, nbad0, nres0;
    reg [7:0] st_v;
    real dgap; integer gaps_ok;
    reg [7:0] syn [0:15];

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_upload_resp_tx);
        repeat (6) @(negedge clk); rst = 0; ticks(4);
        check(tx === 1'b1 && !resp_busy && !overflow, "reset: line idle high, nothing queued, no overflow");

        // ---- 1. one frame of every type; raw bytes checked exactly
        snap;
        ev_ack_p(7'd0);   wait_idle;
        ev_ack_p(7'd37);  wait_idle;
        ev_commit_p;      wait_idle;
        check(nraw == r0 + 12 && n_good == g0 + 3 && n_bad == 0, "3 events -> 3 frames, 12 bytes on the wire, no bad frames");
        check(raw[(r0+0)%1024] === 8'h5A && raw[(r0+1)%1024] === 8'h06 && raw[(r0+2)%1024] === 8'h00 && raw[(r0+3)%1024] === 8'h06,
              "ACK entries=0:    5A 06 00 06");
        check(raw[(r0+4)%1024] === 8'h5A && raw[(r0+5)%1024] === 8'h06 && raw[(r0+6)%1024] === 8'h25 && raw[(r0+7)%1024] === 8'h23,
              "ACK entries=37:   5A 06 25 23");
        check(raw[(r0+8)%1024] === 8'h5A && raw[(r0+9)%1024] === 8'h07 && raw[(r0+10)%1024] === 8'h40 && raw[(r0+11)%1024] === 8'h47,
              "COMMITTED (64):   5A 07 40 47");
        snap;
        for (i = 1; i <= 10; i = i + 1) begin ev_nak_p(i[3:0]); wait_idle; end
        ok = 1;
        for (i = 1; i <= 10; i = i + 1)
            if (!(raw[(r0+4*(i-1))%1024] === 8'h5A && raw[(r0+4*(i-1)+1)%1024] === 8'h15 &&
                  raw[(r0+4*(i-1)+2)%1024] === i[7:0] && raw[(r0+4*(i-1)+3)%1024] === (8'h15 ^ i[7:0]))) ok = 0;
        check(ok && n_good == g0 + 10 && nraw == r0 + 40, "NAK error codes 1..10: 5A 15 <code> <15^code>");

        // ---- 2. frame properties, exhaustive over the whole specification
        ok = 1;
        for (i = 0; i <= 64; i = i + 1) for (k = 0; k < 2; k = k + 1) begin
            st_v = 8'h06 | (k ? 8'h80 : 0);
            if (st_v == 8'h5A || i[7:0] == 8'h5A || spec_chk(st_v, i[7:0]) == 8'h5A) ok = 0;
        end
        for (k = 0; k < 2; k = k + 1) begin
            st_v = 8'h07 | (k ? 8'h80 : 0);
            if (st_v == 8'h5A || spec_chk(st_v, 8'd64) == 8'h5A) ok = 0;
        end
        for (i = 1; i <= 10; i = i + 1) for (k = 0; k < 2; k = k + 1) begin
            st_v = 8'h15 | (k ? 8'h80 : 0);
            if (st_v == 8'h5A || i[7:0] == 8'h5A || spec_chk(st_v, i[7:0]) == 8'h5A) ok = 0;
        end
        check(ok, "spec: 0x5A never occurs in STATUS, INFO or CHK of any possible frame (so SOF is unambiguous)");
        // the DUT really sends what the spec says, for every ACK count 0..64
        snap;
        for (i = 0; i <= 64; i = i + 1) begin ev_ack_p(i[6:0]); wait_idle; end
        ok = 1;
        for (i = 0; i <= 64; i = i + 1)
            if (!(f_st[(g0+i)%512] === 8'h06 && f_info[(g0+i)%512] === i[7:0])) ok = 0;
        check(ok && n_good == g0 + 65 && n_bad == 0 && n_resync == 0, "all 65 ACK entry counts (0..64) sent and parsed correctly");

        // ---- 3. back-to-back events: order kept, bytes contiguous (no gap between frames)
        snap;
        burst(4, 11);
        wait_idle;
        check(n_good == g0 + 4, "4 events on consecutive clocks -> 4 frames");
        exp_f(0, 8'h06, 11, 0, "frame 1 = event 11");
        exp_f(1, 8'h06, 12, 0, "frame 2 = event 12");
        exp_f(2, 8'h06, 13, 0, "frame 3 = event 13");
        exp_f(3, 8'h06, 14, 0, "frame 4 = event 14");
        gaps_ok = 1;
        for (i = 1; i < 16; i = i + 1) begin
            dgap = bt[(r0+i)%1024] - bt[(r0+i-1)%1024];
            if (!(dgap > 10 * BIT - 1.0 && dgap < 10 * BIT + 1.0)) gaps_ok = 0;
        end
        check(gaps_ok, "16 bytes of 4 queued frames are exactly 10 bit times apart (continuous stream)");
        check(!overflow, "no overflow below the queue capacity");

        // ---- 4. overflow: capacity is DEPTH queued + 1 in flight = 5 responses
        snap;
        burst(8, 21);                       // 21..28: 21..25 fit, 26..28 dropped
        check(overflow, "overflow flag set when a response had to be dropped");
        wait_idle;
        check(n_good == g0 + 5, "burst of 8 into an empty queue: exactly 5 frames delivered (DEPTH+1)");
        exp_f(0, 8'h06, 21, 0, "order kept: 21");  exp_f(1, 8'h06, 22, 0, "order kept: 22");
        exp_f(2, 8'h06, 23, 0, "order kept: 23");  exp_f(3, 8'h06, 24, 0, "order kept: 24");
        exp_f(4, 8'h06, 25, 0, "order kept: 25 (no lost flag yet, the loss is AFTER it)");
        snap; ev_ack_p(7'd29); wait_idle;
        exp_f(0, 8'h06, 29, 1, "next response after the loss carries the lost flag");
        snap; ev_ack_p(7'd30); wait_idle;
        exp_f(0, 8'h06, 30, 0, "flag cleared again: following response is normal");
        check(overflow, "overflow output is sticky");

        // ---- 5. repeated overflow: more drops while still full, then drain
        snap;
        burst(8, 31);                       // 31..35 delivered, 36..38 dropped
        ticks(40);
        burst(3, 41);                       // queue still full: 41..43 dropped as well
        wait_idle;
        check(n_good == g0 + 5, "second burst plus 3 more while full: still only 5 frames");
        exp_f(0, 8'h06, 31, 0, "31"); exp_f(1, 8'h06, 32, 0, "32"); exp_f(2, 8'h06, 33, 0, "33");
        exp_f(3, 8'h06, 34, 0, "34"); exp_f(4, 8'h06, 35, 0, "35");
        snap; ev_nak_p(4'd9); wait_idle;
        exp_f(0, 8'h15, 9, 1, "NAK after repeated drops: one lost flag (not one per drop)");
        snap; ev_ack_p(7'd50); wait_idle;
        exp_f(0, 8'h06, 50, 0, "and the following response is clean");

        // ---- 5b. partial drain: queue has room for one when the next burst arrives
        snap;
        burst(8, 51);                       // 51 in flight, 52..55 queued, 56..58 dropped
        ticks(FRAME_CLKS + 40);             // first frame done: 52 now in flight, room for exactly 1
        burst(3, 61);                       // 61 queued, 62 and 63 dropped
        wait_idle;
        ev_ack_p(7'd64); wait_idle;
        check(n_good == g0 + 7, "partial drain: 5 + 1 delivered, then the flagged one");
        exp_f(0, 8'h06, 51, 0, "51"); exp_f(1, 8'h06, 52, 0, "52"); exp_f(2, 8'h06, 53, 0, "53");
        exp_f(3, 8'h06, 54, 0, "54"); exp_f(4, 8'h06, 55, 0, "55");
        exp_f(5, 8'h06, 61, 1, "61 takes the freed slot, flagged for the earlier drops of 56..58");
        exp_f(6, 8'h06, 64, 1, "64 flagged for the drops of 62 and 63");

        // ---- 6. reset during transmission
        // flush state, then queue 3 events plus drops so that lost_pend and the FIFO are both non-empty
        wait_idle;
        snap; nbad0 = n_bad; nres0 = n_resync;
        burst(8, 1);                        // 1 in flight, 2..5 queued, 6..8 dropped (lost_pend set)
        ticks(2 * 16 * 10 + 8 * 16);        // 2.8 bytes into the first frame: inside INFO
        @(negedge clk); rst = 1;
        @(negedge clk);
        check(tx === 1'b1 && !tx_busy && !resp_busy, "reset mid-frame: TX idle high on the next clock, queue empty");
        check(!overflow, "reset clears the overflow flag");
        ticks(2); rst = 0;
        k = nraw; ticks(4 * FRAME_CLKS);
        check(tx === 1'b1 && resp_busy === 1'b0, "after reset: nothing queued, line stays idle for 4 frame times");
        check(nraw <= k + 1, "no further bytes after the cut-off (at most the byte that was being decoded)");
        snap; ev_ack_p(7'd60); wait_idle;
        check(n_good == g0 + 1, "exactly one good frame after reset (the truncated frame and the dropped queue are gone)");
        exp_f(0, 8'h06, 60, 0, "first response after reset is clean: no stale lost flag");

        // ---- 6b. reset exactly at the start of a frame and right after an event
        snap;
        @(negedge clk); ev_ack = 1; ev_entries = 7'd5; @(negedge clk); ev_ack = 0; rst = 1; @(negedge clk); @(negedge clk); rst = 0;
        ticks(2 * FRAME_CLKS);
        check(n_good == g0 && tx === 1'b1, "event and reset in adjacent clocks: no response, line idle");
        @(negedge clk); rst = 1; ev_ack = 1; ev_entries = 7'd6; @(negedge clk); ev_ack = 0; @(negedge clk); rst = 0;
        ticks(2 * FRAME_CLKS);
        check(n_good == g0 && tx === 1'b1, "event during reset is ignored");
        snap; ev_nak_p(4'd3); wait_idle;
        exp_f(0, 8'h15, 3, 0, "recovers: next NAK sent normally");

        // ---- 7. host-parser resynchronisation after truncated frames (pure parser test, synthetic bytes)
        pst = 0;
        snap; nbad0 = n_bad;
        pfeed(8'h5A);                                                           // truncated after SOF
        pfeed(8'h5A); pfeed(8'h06); pfeed(8'h10); pfeed(8'h16);                 // valid ACK 16
        pfeed(8'h5A); pfeed(8'h06);                                             // truncated after STATUS
        pfeed(8'h5A); pfeed(8'h15); pfeed(8'h03); pfeed(8'h16);                 // valid NAK 3
        pfeed(8'h5A); pfeed(8'h15); pfeed(8'h07);                               // truncated before CHK
        pfeed(8'h5A); pfeed(8'h07); pfeed(8'h40); pfeed(8'h47);                 // valid COMMITTED
        pfeed(8'h00); pfeed(8'hFF); pfeed(8'h80);                               // line garbage between frames
        pfeed(8'h5A); pfeed(8'h5A); pfeed(8'h5A);                               // repeated SOFs only
        pfeed(8'h5A); pfeed(8'h86); pfeed(8'h12); pfeed(8'h94);                 // valid ACK 18 with lost flag
        check(n_good == g0 + 4 && n_bad == nbad0, "4 valid frames recovered from truncated/garbled stream, none invented");
        exp_f(0, 8'h06, 16, 0, "resync: ACK 16"); exp_f(1, 8'h15, 3, 0, "resync: NAK 3");
        exp_f(2, 8'h07, 64, 0, "resync: COMMITTED"); exp_f(3, 8'h06, 18, 1, "resync: ACK 18 with lost flag");
        snap; nbad0 = n_bad;
        pfeed(8'h5A); pfeed(8'h06); pfeed(8'h05); pfeed(8'h00);                 // wrong CHK
        pfeed(8'h5A); pfeed(8'h09); pfeed(8'h01); pfeed(8'h08);                 // impossible STATUS, valid CHK
        pfeed(8'h5A); pfeed(8'h06); pfeed(8'h41); pfeed(8'h47);                 // INFO 65 out of range
        pfeed(8'h5A); pfeed(8'h06); pfeed(8'h01); pfeed(8'h07);                 // good frame right after bad ones
        check(n_good == g0 + 1 && n_bad == nbad0 + 3, "bad checksum / impossible STATUS / bad INFO rejected, good frame still found");

        $display("INFO  parser totals: good=%0d bad=%0d resync=%0d, bytes on wire=%0d, framing errors=%0d", n_good, n_bad, n_resync, nraw, mfe);
        check(mfe == 0, "no framing errors seen on the wire at any point (the cut-off byte reads as 1s, not as a stop-bit error)");
        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #400_000_000; $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
