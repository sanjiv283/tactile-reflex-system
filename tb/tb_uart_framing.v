`timescale 1ns/1ps
// UART framing verification (uart_rx, uart_tx and the ai_uart_bridge packet layer).
// Added to close a gap found by mutation testing: a receiver that ignores the stop bit used to pass every testbench.
// All stimulus is driven on the falling clock edge. CPB = clocks per bit (small, to keep the simulation fast).
//   RX cases: valid frames, start-bit glitches, bad stop bit, break condition, 7-bit / 9-bit / two-stop-bit frames,
//             truncated frame, back-to-back frames, recovery after a framing error, reset in the middle of a frame.
//   TX cases: start/data/stop structure, exact bit timing, frame length, back-to-back bytes, reset during transmission.
//   Bridge cases: framing errors inside an A5 D ~D packet must never be accepted as a packet.
// Documented, inherent 8N1 behaviour (asserted below as such, NOT as a defect): a frame truncated to fewer data bits followed by idle
// is decoded with the missing bits read as 1, because an idle line is indistinguishable from data ones; the packet layer rejects it.
module tb_uart_framing;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    localparam CPB = 16;
    reg line = 1;
    wire [7:0] rb; wire rv;
    uart_rx #(.CLKS_PER_BIT(CPB)) rx (.clk(clk), .rst_n(rst_n), .rxd(line), .data(rb), .valid(rv));
    wire [15:0] g; ai_uart_bridge #(.CLKS_PER_BIT(CPB)) br (.clk(clk), .rst_n(rst_n), .rxd(line), .ai_gpio(g));

    // transmitter under test
    reg [7:0] tdata = 0; reg tsend = 0; wire tbusy, ttx;
    uart_tx #(.CLKS_PER_BIT(CPB)) tx (.clk(clk), .rst_n(rst_n), .data(tdata), .send(tsend), .busy(tbusy), .txd(ttx));

    // receive log
    integer nrx = 0; reg [7:0] rlog [0:255]; integer valid_during_reset = 0;
    always @(posedge clk) if (rv) begin rlog[nrx] = rb; nrx = nrx + 1; if (!rst_n) valid_during_reset = valid_during_reset + 1; end

    integer pass = 0, fail = 0, vectors = 0;
    task check(input c, input [447:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL @%0t: %0s", $time, msg); end end endtask
    task bit_(input b); begin line = b; repeat (CPB) @(negedge clk); end endtask
    task frame(input [7:0] d, input stopb); integer k; begin vectors = vectors + 1; bit_(1'b0); for (k = 0; k < 8; k = k + 1) bit_(d[k]); bit_(stopb); end endtask
    task idle(input integer bits); begin line = 1; repeat (bits * CPB) @(negedge clk); end endtask
    task settle; begin repeat (3 * CPB) @(negedge clk); end endtask
    integer n0, i;

    // ---- transmitter monitor: records the line sampled at the centre of each bit of the next frame ----
    reg [9:0] tbits; integer tstart_clk, tend_clk, tclk = 0, tbusy_clks = 0, frames_seen = 0, tx_bad_timing = 0;
    always @(posedge clk) tclk <= tclk + 1;
    task capture_tx_frame; integer k, t_fall; begin
        @(negedge ttx); t_fall = tclk;                                  // falling edge of the start bit
        for (k = 0; k < 10; k = k + 1) begin repeat (k == 0 ? CPB / 2 : CPB) @(posedge clk); tbits[k] = ttx; end
        frames_seen = frames_seen + 1; tstart_clk = t_fall;
    end endtask

    integer b2b_gap = -1, last_end = 0, first_frame_done = 0;
    task capture_tx_frame2(output [9:0] bits); integer k, t_fall; begin
        @(negedge ttx); t_fall = tclk;
        if (first_frame_done) b2b_gap = t_fall - last_end;
        for (k = 0; k < 10; k = k + 1) begin repeat (k == 0 ? CPB / 2 : CPB) @(posedge clk); bits[k] = ttx; end
        last_end = t_fall + 10 * CPB; first_frame_done = 1;
    end endtask

    initial begin
        repeat (4) @(negedge clk); rst_n = 1; idle(2);

        // ---------- RX: valid frames ----------
        n0 = nrx; frame(8'h55, 1); idle(1); frame(8'hA5, 1); idle(1); frame(8'h00, 1); idle(1); frame(8'hFF, 1); settle;
        check(nrx - n0 == 4, "4 valid frames -> 4 bytes");
        check(rlog[n0] == 8'h55 && rlog[n0+1] == 8'hA5 && rlog[n0+2] == 8'h00 && rlog[n0+3] == 8'hFF, "valid frames: byte values and order");

        // ---------- RX: invalid start bit (glitch shorter than half a bit) ----------
        n0 = nrx; line = 0; repeat (CPB / 4) @(negedge clk); line = 1; idle(3);
        check(nrx == n0, "start-bit glitch (quarter bit): no byte");
        line = 0; repeat (CPB / 2 - 4) @(negedge clk); line = 1; idle(3);
        check(nrx == n0, "start-bit glitch (just under half a bit): no byte");
        frame(8'h3C, 1); settle; check(nrx == n0 + 1 && rlog[n0] == 8'h3C, "recovery after start-bit glitches: next valid frame received");

        // ---------- RX: bad stop bit (framing error) ----------
        n0 = nrx; frame(8'hA5, 0); idle(2); settle; check(nrx == n0, "stop bit = 0: framing error, byte NOT delivered");
        frame(8'hC3, 1); settle; check(nrx == n0 + 1 && rlog[n0] == 8'hC3, "recovery after a framing error: next valid frame received");
        n0 = nrx; frame(8'h00, 0); idle(2); settle; check(nrx == n0, "all-zero data with stop bit 0: dropped");
        frame(8'hFF, 0); idle(2); settle; check(nrx == n0, "all-one data with stop bit 0: dropped");

        // ---------- RX: break condition (line held low) ----------
        n0 = nrx; line = 0; repeat (14 * CPB) @(negedge clk); idle(3); settle;
        check(nrx == n0, "break (line low for 14 bit times): no bytes");
        frame(8'h99, 1); settle; check(nrx == n0 + 1 && rlog[n0] == 8'h99, "recovery after a break");

        // ---------- RX: frame length variants ----------
        n0 = nrx; bit_(1'b0); idle(10); settle;      // one full low bit then idle == a start bit followed by eight 1s: a legitimate 0xFF frame
        check(nrx == n0 + 1 && rlog[n0] == 8'hFF, "one full low bit then idle: decoded as 0xFF (inherent 8N1 behaviour), exactly one byte");
        n0 = nrx; bit_(1'b0); for (i = 0; i < 8; i = i + 1) bit_(8'h5A >> i & 1'b1); bit_(1'b0); idle(3); settle;
        check(nrx == n0, "9-bit frame (extra low bit in the stop slot): framing error, dropped");
        n0 = nrx; frame(8'h42, 1); idle(1); settle; check(nrx == n0 + 1 && rlog[n0] == 8'h42, "two stop bits are accepted");
        n0 = nrx; vectors = vectors + 1; bit_(1'b0); for (i = 0; i < 7; i = i + 1) bit_(8'h35 >> i & 1'b1); idle(4); settle;
        check(nrx == n0 + 1 && rlog[n0] == {1'b1, 7'h35}, "7-bit frame + idle: decoded with the missing bit read as 1 (inherent 8N1 behaviour), exactly one byte");
        n0 = nrx; vectors = vectors + 1; bit_(1'b0); bit_(1'b0); bit_(1'b1); bit_(1'b0); idle(4); settle;    // interrupted: start + 3 bits, then idle
        check(nrx == n0 + 1 && rlog[n0] == 8'hFA, "frame interrupted after 3 data bits: padded with ones by the idle line, exactly one byte");
        frame(8'h6E, 1); settle; check(nrx == n0 + 2 && rlog[n0 + 1] == 8'h6E, "recovery after the interrupted frame");

        // ---------- RX: back-to-back frames ----------
        n0 = nrx; for (i = 0; i < 8; i = i + 1) frame(8'h10 + i, 1); settle;
        check(nrx - n0 == 8, "8 back-to-back frames (no idle): 8 bytes");
        check(rlog[n0] == 8'h10 && rlog[n0+3] == 8'h13 && rlog[n0+7] == 8'h17, "back-to-back frames: values in order");
        n0 = nrx; frame(8'h77, 0); idle(1); frame(8'h88, 1); frame(8'h99, 1); settle;
        check(nrx - n0 == 2 && rlog[n0] == 8'h88 && rlog[n0+1] == 8'h99, "bad-stop frame, one idle bit, then two good frames: only the good ones delivered");

        // ---------- RX: reset in the middle of a frame ----------
        n0 = nrx; valid_during_reset = 0;
        vectors = vectors + 1; bit_(1'b0); for (i = 0; i < 3; i = i + 1) bit_(8'hEE >> i & 1'b1);
        rst_n = 0; repeat (6) @(negedge clk); rst_n = 1;
        for (i = 3; i < 8; i = i + 1) bit_(8'hEE >> i & 1'b1); bit_(1'b1); idle(4); settle;
        check(valid_during_reset == 0, "reset mid-frame: valid never asserted while reset is active");
        check(nrx - n0 <= 1, "reset mid-frame: at most one spurious byte from the frame remainder (UART cannot resynchronise mid-frame)");
        n0 = nrx; frame(8'h12, 1); settle; check(nrx == n0 + 1 && rlog[n0] == 8'h12, "after reset mid-frame: the next frame is received intact");

        // ---------- RX: line held LOW across the release of reset (a break / half-received frame when the FPGA comes out of reset) ----------
        n0 = nrx; line = 0; repeat (2 * CPB) @(negedge clk); rst_n = 0; repeat (6) @(negedge clk); rst_n = 1;
        repeat (3 * CPB) @(negedge clk); line = 1; idle(14); settle;     // low for 3 more bit times, then idle: must NOT be decoded as a frame
        check(nrx == n0, "line held low through the release of reset: no spurious byte (receiver waits for idle)");
        frame(8'h21, 1); settle; check(nrx == n0 + 1 && rlog[n0] == 8'h21, "after that break: the next frame is received intact");

        // ---------- Bridge: framing errors inside an AI packet ----------
        rst_n = 0; repeat (3) @(negedge clk); rst_n = 1; idle(2);      // known bridge state
        begin : bridge
            reg [7:0] hb0;
            hb0 = g[15:8];
            frame(8'hA5, 1); frame(8'h16, 0); frame(8'hE9, 1); idle(2); settle;       // data byte has a bad stop bit -> dropped
            check(g[15:8] == hb0, "packet with a framing error in the DATA byte: not accepted");
            frame(8'hA5, 1); frame(8'h16, 1); frame(8'hE9, 0); idle(2); settle;       // checksum byte has a bad stop bit -> dropped
            check(g[15:8] == hb0, "packet with a framing error in the CHECKSUM byte: not accepted");
            frame(8'hA5, 0); frame(8'h16, 1); frame(8'hE9, 1); idle(2); settle;       // header byte has a bad stop bit -> dropped
            check(g[15:8] == hb0, "packet with a framing error in the HEADER byte: not accepted");
            frame(8'hA5, 1); frame(8'h16, 1); frame(8'hE9, 1); idle(2); settle;       // clean packet
            check(g[15:8] == hb0 + 8'd1 && g[1:0] == 2'd2 && g[6] == 1'b1, "clean packet after the corrupted ones: accepted (class 2, valid)");
            hb0 = g[15:8];
            for (i = 0; i < 6; i = i + 1) begin frame(8'h00, 0); idle(1); end settle;     // storm of framing errors
            check(g[15:8] == hb0 && g[1:0] == 2'd2, "framing-error storm: AI word unchanged");
            frame(8'hA5, 1); frame(8'h13, 1); frame(8'hEC, 1); idle(2); settle;
            check(g[15:8] == hb0 + 8'd1 && g[1:0] == 2'd3, "good packet after the storm: accepted (class 3)");
        end

        // ---------- TX: frame structure and timing ----------
        rst_n = 0; repeat (3) @(negedge clk); rst_n = 1; repeat (4) @(negedge clk);
        check(ttx === 1'b1 && tbusy === 1'b0, "TX idle: line high, not busy");
        fork
            capture_tx_frame;
            begin @(negedge clk); tdata = 8'h55; tsend = 1; @(negedge clk); tsend = 0; end
        join
        check(tbits[0] === 1'b0, "TX start bit is 0");
        check(tbits[8:1] === 8'h55, "TX data bits LSB first (0x55)");
        check(tbits[9] === 1'b1, "TX stop bit is 1");
        wait (!tbusy); repeat (2) @(negedge clk); check(ttx === 1'b1, "TX returns to idle high");
        fork
            capture_tx_frame;
            begin @(negedge clk); tdata = 8'hA3; tsend = 1; @(negedge clk); tsend = 0; end
        join
        check(tbits === {1'b1, 8'hA3, 1'b0}, "TX frame 0xA3: start 0, data 10100011 LSB first, stop 1");
        // frame length: busy must stay high for exactly 10 bit times
        wait (!tbusy); @(negedge clk); tbusy_clks = 0; tdata = 8'h0F; tsend = 1; @(negedge clk); tsend = 0;
        while (tbusy) begin tbusy_clks = tbusy_clks + 1; @(negedge clk); end
        check(tbusy_clks >= 10 * CPB - 2 && tbusy_clks <= 10 * CPB + 2, "TX frame occupies 10 bit times (busy length)");
        // bit-width of an alternating pattern: every bit exactly CPB clocks
        fork
            begin : widths
                integer w0, w1, ok; ok = 1; @(negedge ttx); w0 = tclk;
                for (i = 0; i < 9; i = i + 1) begin @(ttx); w1 = tclk; if (w1 - w0 != CPB) ok = 0; w0 = w1; end
                check(ok == 1, "TX 0x55: every bit lasts exactly CLKS_PER_BIT clocks");
            end
            begin @(negedge clk); wait (!tbusy); @(negedge clk); tdata = 8'h55; tsend = 1; @(negedge clk); tsend = 0; end
        join
        wait (!tbusy);
        // back-to-back bytes: the second start bit must follow the first stop bit with at most 3 idle clocks
        begin : b2b
            reg [9:0] f1, f2; integer gap, t_end1, t_start2;
            fork
                begin capture_tx_frame2(f1); capture_tx_frame2(f2); end
                begin @(negedge clk); tdata = 8'hC1; tsend = 1; @(negedge clk); tsend = 0; while (tbusy) @(negedge clk); tdata = 8'h2D; tsend = 1; @(negedge clk); tsend = 0; end
            join
            check(f1 === {1'b1, 8'hC1, 1'b0} && f2 === {1'b1, 8'h2D, 1'b0}, "TX back-to-back bytes 0xC1, 0x2D: both frames intact");
            check(b2b_gap >= 0 && b2b_gap <= 3, "TX back-to-back: at most 3 idle clocks between stop bit and next start bit");
        end
        wait (!tbusy); repeat (4) @(negedge clk); check(ttx === 1'b1 && tbusy === 1'b0, "TX idle after back-to-back sends");
        // reset during transmission
        @(negedge clk); tdata = 8'h00; tsend = 1; @(negedge clk); tsend = 0; repeat (CPB * 3) @(negedge clk);
        check(tbusy === 1'b1 && ttx === 1'b0, "TX mid-frame (data bit 0 of 0x00): busy, line low");
        rst_n = 0; @(negedge clk); @(negedge clk); check(tbusy === 1'b0 && ttx === 1'b1, "reset during transmission: line idles high, not busy");
        rst_n = 1; repeat (4) @(negedge clk);
        fork
            capture_tx_frame;
            begin @(negedge clk); tdata = 8'h96; tsend = 1; @(negedge clk); tsend = 0; end
        join
        check(tbits === {1'b1, 8'h96, 1'b0}, "TX works normally after a reset during transmission");

        $display("TB tb_uart_framing: PASS %0d FAIL %0d VECTORS %0d", pass, fail, vectors);
        $finish;
    end
    initial begin #80_000_000; $display("TB tb_uart_framing: TIMEOUT"); $finish; end
endmodule
