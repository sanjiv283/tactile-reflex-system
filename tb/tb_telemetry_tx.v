`timescale 1ns/1ps
// telemetry_tx unit test: frame = 0x5A, {flags[3:0], force[11:8]}, force[7:0], one frame per PERIOD clocks. Decoded with an independent uart_rx.
// Covers: header byte, flag nibble order, force split, all 16 flag values x several force codes, constant frame spacing (no jitter, no overlap),
// idle line between frames, reset in the middle of a frame (no partial frame, restart with a header).
module tb_telemetry_tx;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    localparam CPB = 16, PERIOD = 1000;
    reg [11:0] force_code = 12'h000; reg [3:0] flags = 4'h0; wire txd;
    telemetry_tx #(.CLKS_PER_BIT(CPB), .PERIOD(PERIOD)) dut (.clk(clk), .rst_n(rst_n), .force_code(force_code), .flags(flags), .txd(txd));
    wire [7:0] rb; wire rv; reg rrst = 0; uart_rx #(.CLKS_PER_BIT(CPB)) rx (.clk(clk), .rst_n(rrst), .rxd(txd), .data(rb), .valid(rv));
    integer pass = 0, fail = 0, vectors = 0, cyc = 0, nb = 0, frames = 0, t_hdr = 0, t_prev = 0, spacing = 0, bad_hdr = 0;
    reg [7:0] b0, b1, b2; reg [11:0] sent_force; reg [3:0] sent_flags;
    task check(input c, input [383:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL @%0t: %0s", $time, msg); end end endtask
    always @(posedge clk) cyc <= cyc + 1;
    always @(posedge clk) if (rv) begin
        if (nb == 0) begin b0 = rb; t_hdr = cyc; end else if (nb == 1) b1 = rb; else b2 = rb;
        nb = nb + 1;
        if (nb == 3) begin nb = 0; frames = frames + 1; end
    end
    task next_frame; integer f0; begin f0 = frames; while (frames == f0) @(posedge clk); end endtask
    task expect_frame(input [11:0] fc, input [3:0] fl); begin
        next_frame; vectors = vectors + 1;
        check(b0 === 8'h5A, "header byte is 0x5A");
        check(b1[7:4] === fl, "flags in the high nibble of byte 1 (safe, sensor_fault, estop, ai_valid)");
        check({b1[3:0], b2} === fc, "force code split over byte 1 low nibble and byte 2");
    end endtask
    integer fl, k; reg [11:0] codes [0:3];
    initial begin
        codes[0] = 12'h000; codes[1] = 12'hFFF; codes[2] = 12'h5A5; codes[3] = 12'hA00;
        repeat (4) @(posedge clk); rrst = 1; repeat (3) @(posedge clk); rst_n = 1;
        repeat (PERIOD / 2) @(posedge clk); check(frames == 0, "nothing is sent before the first period elapses");
        // all 16 flag values with one force code each time round, 4 force codes overall
        for (k = 0; k < 4; k = k + 1) for (fl = 0; fl < 16; fl = fl + 1) begin
            force_code = codes[k]; flags = fl[3:0];
            @(negedge clk); // the new values are latched when the next period starts; wait out the frame in flight first
            next_frame; expect_frame(codes[k], fl[3:0]);
        end
        // spacing between frame starts: three consecutive frames, all identical (no jitter) and longer than a frame (no overlap)
        force_code = 12'h123; flags = 4'h9; next_frame; t_prev = t_hdr; next_frame; spacing = t_hdr - t_prev;
        $display("INFO telemetry frame spacing = %0d clocks for PERIOD = %0d", spacing, PERIOD);
        check(spacing >= PERIOD && spacing <= PERIOD + 3 * 10 * CPB + 8, "frame spacing is PERIOD plus at most one frame time of transmission");
        t_prev = t_hdr; next_frame; check(t_hdr - t_prev == spacing, "frame spacing identical on the next frame (no jitter)");
        t_prev = t_hdr; next_frame; check(t_hdr - t_prev == spacing, "frame spacing identical again");
        check(spacing > 3 * 10 * CPB, "frames never overlap (spacing longer than one frame time)");
        // idle between frames
        @(posedge clk); wait (rv == 1'b0); repeat (3 * 10 * CPB + 40) @(posedge clk); check(txd === 1'b1, "line idles high between frames");
        // reset in the middle of a frame: nothing partial, then a clean frame with a header
        next_frame; while (nb == 0) @(posedge clk); repeat (CPB * 4) @(posedge clk);
        @(negedge clk); rst_n = 0; rrst = 0; repeat (4) @(posedge clk); rst_n = 1; rrst = 1; nb = 0;
        repeat (PERIOD / 2) @(posedge clk); check(nb == 0, "after a reset nothing is sent before the next period");
        force_code = 12'hC3C; flags = 4'h6; expect_frame(12'hC3C, 4'h6);
        $display("TB tb_telemetry_tx: PASS %0d FAIL %0d VECTORS %0d NOTE telemetry_tx alone, decoded by an independent uart_rx; PERIOD=%0d", pass, fail, vectors, PERIOD); $finish;
    end
    initial begin #20_000_000; $display("TB tb_telemetry_tx: TIMEOUT"); $finish; end
endmodule
