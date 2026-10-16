`timescale 1ns / 1ps
// Direct tests of rtl/servo_pwm_generator.v: exact pulse widths, exact frame period, pulse latched once per frame,
// zero width, and reset behaviour. Everything is measured in CLOCK COUNTS (no real-time tolerance), so a one-clock
// error is detected at every supported clock rate.
// Run with different clocks / frame lengths via -P (see run_sim.sh). Default: 1 MHz clock, the real 20 ms frame.
module tb_servo_pwm;
    parameter CLK_HZ   = 1_000_000;     // whole MHz required by the module
    parameter FRAME_US = 20000;
    localparam TICKS   = CLK_HZ / 1_000_000;           // clocks per microsecond
    localparam FRAME_CLKS = FRAME_US * TICKS;
    localparam real T  = 1.0e9 / CLK_HZ;

    reg clk = 0;
    always #(T/2.0) clk = ~clk;

    reg         rst = 1;
    reg  [11:0] pulse_us = 12'd1500;
    wire        servo_out;
    servo_pwm_generator #(.CLK_HZ(CLK_HZ), .FRAME_US(FRAME_US)) dut (
        .clk(clk), .rst(rst), .pulse_us(pulse_us), .servo_out(servo_out));

    integer errors = 0;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask

    // ---- edge / width monitor, sampled on posedge (so every measurement has the same constant offset)
    integer cyc = 0, hi = 0, nrise = 0, nwid = 0, rst_rel_cyc = -1;
    integer rise_cyc [0:255];
    integer wid_clk  [0:255];
    reg prev = 0, cur = 0, prev_rst = 1;
    always @(posedge clk) begin
        cur = servo_out;
        if (prev_rst && !rst && rst_rel_cyc < 0) rst_rel_cyc = cyc;
        prev_rst = rst;
        if (cur === 1'b1 && prev === 1'b0) begin rise_cyc[nrise % 256] = cyc; nrise = nrise + 1; hi = 0; end
        if (cur === 1'b1) hi = hi + 1;
        if (cur === 1'b0 && prev === 1'b1) begin wid_clk[nwid % 256] = hi; nwid = nwid + 1; end
        prev = cur;
        cyc = cyc + 1;
    end

    task wait_rises(input integer n);               // wait until n pulses have started
        begin while (nrise < n) @(posedge clk); end
    endtask
    task nclk(input integer n); repeat (n) @(posedge clk); endtask

    integer i, r0, k;
    reg ok;
    reg [11:0] seq [0:5];

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_servo_pwm);
        $display("INFO  CLK_HZ=%0d FRAME_US=%0d -> %0d clocks/us, %0d clocks/frame", CLK_HZ, FRAME_US, TICKS, FRAME_CLKS);

        // ---- reset: output low, stays low
        nclk(10);
        check(servo_out === 1'b0, "reset: servo_out low");
        nclk(2 * FRAME_CLKS / 3);
        check(nrise == 0 && servo_out === 1'b0, "reset held longer than a frame: no pulse");
        @(negedge clk) rst = 0;

        // ---- characterise the first pulse after reset: pulse_latched is cleared by reset, so the first frame is empty
        wait_rises(1);
        k = rise_cyc[0] - rst_rel_cyc;
        $display("INFO  first pulse starts %0d clocks after reset release (frame = %0d clocks)", k, FRAME_CLKS);
        check(k >= FRAME_CLKS && k <= FRAME_CLKS + 3, "after reset the first pulse starts one full frame later (first frame is empty)");

        // ---- steady state: exact width and exact period, several frames
        wait_rises(4);
        wait (nwid >= 3);
        ok = 1; for (i = 0; i < 3; i = i + 1) if (wid_clk[i] != 1500 * TICKS) ok = 0;
        check(ok, "1500 us pulse is exactly 1500*TICKS clocks high, three frames in a row");
        ok = 1; for (i = 1; i < 4; i = i + 1) if (rise_cyc[i] - rise_cyc[i-1] != FRAME_CLKS) ok = 0;
        check(ok, "frame period (rising edge to rising edge) is exactly FRAME_US*TICKS clocks");

        // ---- latched once per frame: a change DURING the pulse waits for the next frame
        // sequence of values; each change is applied one clock after a rising edge (mid-pulse) or half a frame later (mid-gap)
        seq[0] = 12'd1000; seq[1] = 12'd2000; seq[2] = 12'd1234; seq[3] = 12'd1750; seq[4] = 12'd1500;
        r0 = nrise;                                           // pulse r0-1 is running, width 1500
        for (i = 0; i < 5; i = i + 1) begin
            wait_rises(r0 + i + 1);                           // pulse (r0+i) starts
            nclk(1);
            if (i % 2 == 0) pulse_us = seq[i];                // mid-pulse change
            else begin nclk(FRAME_CLKS / 2); pulse_us = seq[i]; end   // mid-gap change
        end
        wait_rises(r0 + 7); wait (nwid >= r0 + 6);
        // widths: pulse (r0-1) = 1500 (old value, still latched); pulse (r0) is the one running when seq[0] was set -> still 1500
        check(wid_clk[(r0 - 1) % 256] == 1500 * TICKS, "pulse running when the command changed keeps its old width");
        ok = 1;
        for (i = 0; i < 5; i = i + 1) if (wid_clk[(r0 + i) % 256] != (i == 0 ? 1500 : seq[i-1]) * TICKS) ok = 0;
        if (!ok) for (i = 0; i < 5; i = i + 1) $display("      pulse %0d: %0d clocks (= %0d us)", r0 + i, wid_clk[(r0+i)%256], wid_clk[(r0+i)%256] / TICKS);
        check(ok, "each new command appears exactly one frame later (mid-pulse and mid-gap changes)");
        check(wid_clk[(r0 + 5) % 256] == seq[4] * TICKS, "last command applied (1500 us)");
        ok = 1; for (i = r0; i < r0 + 6; i = i + 1) if (rise_cyc[i % 256] - rise_cyc[(i-1) % 256] != FRAME_CLKS) ok = 0;
        check(ok, "frame period stays exact while the width changes every frame");

        // ---- zero width: the pulse already running keeps its width, then the next frame is silent
        i = nrise; wait_rises(i + 1); nclk(1); pulse_us = 12'd0;        // pulse #(i+1) is running when 0 is commanded
        nclk(FRAME_CLKS + FRAME_CLKS / 2);                              // 1.5 frames later
        check(nrise == i + 1 && servo_out === 1'b0, "pulse_us = 0: the frame after the change has no pulse (output stays low)");
        wait (nwid >= i + 1);
        check(wid_clk[i % 256] == 1500 * TICKS, "the pulse running when 0 was commanded kept its width");
        pulse_us = 12'd1500;
        wait_rises(i + 2); wait (nwid >= i + 2);
        check(wid_clk[(i + 1) % 256] == 1500 * TICKS, "pulses resume with the correct width after a silent frame");

        // ---- reset in the middle of a pulse: low at once, one empty frame, then pulses resume
        wait_rises(nrise + 1); nclk(500 * TICKS);               // 500 us into the pulse
        check(servo_out === 1'b1, "mid-pulse before reset: output high");
        @(negedge clk) rst = 1;
        nclk(2);
        check(servo_out === 1'b0, "reset mid-pulse: output low within 2 clocks");
        nclk(4); @(negedge clk) rst = 0;
        i = nrise; r0 = cyc;
        nclk(FRAME_CLKS - 10);
        check(nrise == i && servo_out === 1'b0, "after a mid-pulse reset the first frame is empty (no pulse)");
        wait_rises(i + 1);
        check(rise_cyc[i % 256] - r0 >= FRAME_CLKS - 4 && rise_cyc[i % 256] - r0 <= FRAME_CLKS + 8, "pulse resumes after one empty frame");
        wait (nwid >= i + 1);
        check(wid_clk[i % 256] == 1500 * TICKS, "resumed pulse has the commanded width (1500 us)");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #(FRAME_US * 1000.0 * 40); $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
