`timescale 1ns/1ps
// Self-checking testbench for adc_spi_interface + mcp3008_model.
// Parameters can be overridden (run_sim.sh reruns at 27 MHz / 1.35 MHz).
module tb_adc_spi_interface #(
    parameter CLK_HZ  = 100_000_000,
    parameter SCLK_HZ = 1_000_000
);
    localparam real    TCLK   = 1.0e9 / CLK_HZ;
    localparam integer HALF   = (CLK_HZ + 2 * SCLK_HZ - 1) / (2 * SCLK_HZ);
    localparam integer PERIOD = 35 * HALF + 1;     // clocks between successive CS falls, back-to-back

    reg clk = 0, rst = 1, start = 0;
    reg [2:0] channel = 0;
    wire cs_n, sclk, mosi, miso, busy, data_valid, frame_err;
    wire [9:0] data;

    adc_spi_interface #(.CLK_HZ(CLK_HZ), .SCLK_HZ(SCLK_HZ)) dut (
        .clk(clk), .rst(rst), .start(start), .channel(channel), .miso(miso),
        .cs_n(cs_n), .sclk(sclk), .mosi(mosi), .busy(busy),
        .data(data), .data_valid(data_valid), .frame_err(frame_err));
    mcp3008_model m (.cs_n(cs_n), .sclk(sclk), .mosi(mosi), .miso(miso));

    always #(TCLK / 2) clk = ~clk;

    integer errors = 0, i;
    task chk(input c, input [255:0] msg);
        if (!c) begin errors = errors + 1; $display("FAIL @%0t: %0s", $time, msg); end
    endtask
    task tick(input integer n); repeat (n) @(negedge clk); endtask

    // event logs
    integer nvalid = 0, nerr = 0, nlog = 0, ncs = 0, vcons = 0;
    reg [9:0] log_data [0:63];
    reg [2:0] log_ch   [0:63];
    real      cs_t     [0:63];
    reg       prev_dv = 0;
    always @(posedge clk) begin
        if (data_valid) begin
            nvalid = nvalid + 1; log_data[nlog] = data; log_ch[nlog] = m.last_ch; nlog = nlog + 1;
        end
        if (frame_err) nerr = nerr + 1;
        if (data_valid && prev_dv) vcons = vcons + 1;     // pulse wider than 1 clock
        prev_dv = data_valid;
    end
    always @(negedge cs_n) begin cs_t[ncs % 64] = $realtime; ncs = ncs + 1; end

    task convert(input [2:0] ch);
        integer v0, e0, g;
        begin
            while (busy) @(negedge clk);
            channel = ch; start = 1; @(negedge clk); start = 0;
            v0 = nvalid; e0 = nerr; g = 0;
            while (nvalid == v0 && nerr == e0 && g < 3 * PERIOD) begin @(negedge clk); g = g + 1; end
        end
    endtask

    integer v0, e0, c0, k;
    reg [9:0] dsave;
    real per;

    initial begin
        for (i = 0; i < 8; i = i + 1) m.chan_val[i] = 0;

        // ---- reset: fixed outputs, no SPI activity even with start held high
        start = 1; channel = 3'd5; tick(3 * HALF);
        chk(cs_n === 1 && sclk === 0 && mosi === 0, "reset: CS high, SCLK/MOSI low");
        chk(data === 0 && data_valid === 0 && frame_err === 0, "reset: data outputs cleared");
        chk(m.frames == 0 && m.aborts == 0 && ncs == 0, "reset: no SPI activity");
        start = 0; rst = 0;

        // ---- known values
        m.chan_val[0] = 0;     convert(0); chk(nvalid == 1 && data == 0,     "value 0");
        m.chan_val[0] = 1023;  convert(0); chk(data == 1023,                 "value 1023");
        m.chan_val[0] = 10'h2AA; convert(0); chk(data == 10'h2AA,            "value 0x2AA");
        m.chan_val[0] = 10'h155; convert(0); chk(data == 10'h155,            "value 0x155");
        m.chan_val[0] = 512;   convert(0); chk(data == 512,                  "value 512");
        chk(nerr == 0, "no frame_err on good data");

        // ---- all 8 channels: value and channel number
        for (i = 0; i < 8; i = i + 1) m.chan_val[i] = 100 + 37 * i;
        for (i = 0; i < 8; i = i + 1) begin
            convert(i);
            chk(data == 100 + 37 * i,    "channel value");
            chk(m.last_ch == i,          "channel number");
        end

        // ---- back-to-back with channel change mid-frame
        m.chan_val[2] = 111; m.chan_val[5] = 555;
        c0 = nlog; k = ncs;
        channel = 2; start = 1;
        @(negedge cs_n); tick(HALF * 10); channel = 5;     // mid-frame change must not affect frame 1
        wait (nlog >= c0 + 6); start = 0;
        chk(log_data[c0] == 111 && log_ch[c0] == 2, "mid-frame channel change affected the frame");
        for (i = 1; i < 6; i = i + 1)
            chk(log_data[c0 + i] == 555 && log_ch[c0 + i] == 5, "following frames use new channel");
        for (i = k + 1; i < k + 6; i = i + 1) begin
            per = (cs_t[i % 64] - cs_t[(i - 1) % 64]) / TCLK;
            chk(per > PERIOD - 0.01 && per < PERIOD + 0.01, "back-to-back period");
        end
        $display("INFO: conversion period = %0d clocks = %0.3f us (%0d Hz clk, %0d Hz SCLK)",
                 PERIOD, PERIOD * TCLK / 1000.0, CLK_HZ, SCLK_HZ);
        while (busy) @(negedge clk);

        // ---- start while busy is ignored
        m.chan_val[0] = 321; v0 = nvalid;
        channel = 0; start = 1; @(negedge clk); start = 0;
        tick(HALF * 8); start = 1; @(negedge clk); start = 0;
        tick(3 * PERIOD);
        chk(nvalid == v0 + 1, "start while busy produced an extra conversion");
        chk(vcons == 0, "data_valid wider than one clock");

        // ---- reset mid-conversion, with start held high through reset
        v0 = nvalid; c0 = m.aborts;
        channel = 0; start = 1; @(negedge clk); start = 0;
        tick(HALF * 12);
        start = 1; rst = 1; tick(3);
        chk(cs_n === 1 && sclk === 0, "mid-conversion reset: CS high, SCLK low");
        start = 0; rst = 0; tick(HALF * 3);
        chk(nvalid == v0, "aborted frame produced data");
        chk(m.aborts == c0 + 1, "model did not see the abort");
        m.chan_val[0] = 700; convert(0);
        chk(data == 700 && nvalid == v0 + 1, "recovery after reset");

        // ---- disconnected MISO: frame_err, no data
        dsave = data; v0 = nvalid; e0 = nerr;
        m.disconnect = 1; convert(0);
        chk(nerr == e0 + 1 && nvalid == v0, "disconnected MISO: expected frame_err and no data");
        chk(data == dsave, "disconnected MISO changed data");
        m.disconnect = 0; m.chan_val[0] = 42; convert(0);
        chk(data == 42, "recovery after reconnect");

        // ---- datasheet timing
        chk(m.violations == 0, "datasheet timing violations in model");
        chk(m.frames > 20, "model saw too few complete frames");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end

    initial begin #200_000_000; $display("FAIL: global timeout"); $finish; end
endmodule
