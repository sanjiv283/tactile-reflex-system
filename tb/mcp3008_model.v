`timescale 1ns / 1ps
// SIMULATION ONLY - not synthesizable. Behavioural MCP3008, SPI mode 0,
// with timing checks against the datasheet limits for VDD = 2.7-3.3 V.
// The testbench sets value[ch] (0..1023) to stand in for the analog inputs.
module mcp3008_model #(
    parameter real T_DO      = 200.0,  // SCLK fall -> DOUT valid (max)
    parameter real T_CLK_MIN = 740.7,  // 1 / 1.35 MHz
    parameter real T_SUCS    = 100.0,  // CS fall -> first SCLK rise (min)
    parameter real T_CSH     = 270.0,  // CS high between conversions (min)
    parameter real T_SU      = 50.0    // DIN setup before SCLK rise (min)
)(
    input  wire cs_n,
    input  wire sclk,
    input  wire din,
    output reg  dout
);
    reg  [9:0] value [0:7];
    integer    conversions = 0, violations = 0, diff_requests = 0;
    reg  [2:0] last_channel = 0;
    realtime   min_period = 1.0e9;

    reg        started;
    integer    k, i;
    reg  [3:0] cfg;
    reg  [9:0] word;
    realtime   t_cs_fall = 0, t_cs_rise = -1.0e9, t_last_rise = -1.0e9, t_din = 0;

    initial begin
        dout = 1'bz; started = 0; k = 0; cfg = 0; word = 0;
        for (i = 0; i < 8; i = i + 1) value[i] = 0;
    end

    task violation(input [8*40-1:0] what);
        begin
            violations = violations + 1;
            $display("MODEL VIOLATION at %0t ns: %0s", $realtime, what);
        end
    endtask

    always @(din) t_din = $realtime;

    always @(negedge cs_n) begin
        t_cs_fall = $realtime;
        if (t_cs_fall - t_cs_rise < T_CSH) violation("CS high time < tCSH");
        if (sclk !== 1'b0)                 violation("SCLK not low at CS fall");
        started = 0; k = 0; cfg = 0; t_last_rise = -1.0e9;
        dout = 1'bz;
    end

    always @(posedge cs_n) begin
        t_cs_rise = $realtime;
        dout = 1'bz;
    end

    always @(posedge sclk) if (cs_n === 1'b0) begin
        if ($realtime - t_cs_fall < T_SUCS) violation("CS setup < tSUCS");
        if (t_last_rise >= 0) begin
            if ($realtime - t_last_rise < min_period) min_period = $realtime - t_last_rise;
            if ($realtime - t_last_rise < T_CLK_MIN)  violation("SCLK faster than 1.35 MHz");
        end
        if ($realtime - t_din < T_SU) violation("DIN setup < tSU");
        t_last_rise = $realtime;
        if (!started) begin
            if (din === 1'b1) begin started = 1; k = 0; end
        end else begin
            k = k + 1;
            if (k <= 4) cfg = {cfg[2:0], din};
        end
    end

    always @(negedge sclk) if (cs_n === 1'b0 && started) begin
        if (k == 5) begin                       // sampling done -> null bit
            if (cfg[3] !== 1'b1) diff_requests = diff_requests + 1;
            word         = value[cfg[2:0]];
            last_channel = cfg[2:0];
            dout <= #(T_DO) 1'b0;
        end else if (k >= 6 && k <= 15) begin   // B9 .. B0
            dout <= #(T_DO) word[15 - k];
            if (k == 15) conversions = conversions + 1;
        end
    end
endmodule
