`timescale 1ns/1ps
// Simulation-only MCP3008 (single-ended, SPI mode 0) with datasheet timing checks.
// Testbench knobs: chan_val[0:7], disconnect (MISO floats to pull-up = 1).
// Observables: violations, frames (complete 17-edge frames), aborts, last_ch, ch_mask.
module mcp3008_model (
    input  cs_n,
    input  sclk,
    input  mosi,
    output miso
);
    localparam real T_SUCS = 100.0;   // CS fall -> first SCLK rise
    localparam real T_CSH  = 270.0;   // CS high time between conversions
    localparam real T_HI   = 200.0;   // SCLK high / low (conservative 3.3 V figure)
    localparam real T_SU   = 50.0;    // MOSI setup before rise
    localparam real T_HD   = 50.0;    // MOSI hold after rise
    localparam real T_DO   = 100.0;   // MISO valid after SCLK fall

    reg [9:0] chan_val [0:7];
    reg       disconnect = 0;
    integer   violations = 0, frames = 0, aborts = 0;
    reg [2:0] last_ch = 0;
    reg [7:0] ch_mask = 0;

    integer   nedge = 0;
    reg [4:0] cfg = 0;
    reg [9:0] vsel = 0;
    reg       miso_r = 0;
    real t_cs_fall = -1e9, t_cs_rise = -1e9, t_rise = -1e9, t_fall = -1e9, t_mosi = -1e9, tf;

    assign miso = (disconnect || cs_n) ? 1'b1 : miso_r;

    task viol(input [255:0] what);
        begin violations = violations + 1; $display("MODEL VIOLATION @%0t: %0s", $time, what); end
    endtask

    always @(negedge cs_n) begin
        if ($realtime - t_cs_rise < T_CSH) viol("tCSH: CS high time too short");
        if (sclk) viol("SCLK high at CS fall");
        t_cs_fall = $realtime; nedge = 0; cfg = 0;
    end

    always @(posedge cs_n) begin
        if (nedge == 17) frames = frames + 1;
        else if (nedge != 0) aborts = aborts + 1;
        t_cs_rise = $realtime; nedge = 0;
    end

    always @(mosi) t_mosi = $realtime;

    always @(posedge sclk) begin
        if (cs_n) viol("SCLK rising while CS high");
        else begin
            if (nedge == 0 && $realtime - t_cs_fall < T_SUCS) viol("tSUCS: CS setup");
            if (nedge > 0 && $realtime - t_fall < T_HI)       viol("tLO: SCLK low time");
            if ($realtime - t_mosi < T_SU)                    viol("tSU: MOSI setup");
            t_rise = $realtime;
            nedge = nedge + 1;
            if (nedge <= 5) cfg = {cfg[3:0], mosi};
            if (nedge == 5) begin
                if (cfg[4:3] != 2'b11) viol("bad start/SGL bits");
                last_ch = cfg[2:0]; ch_mask = ch_mask | (8'd1 << cfg[2:0]);
                vsel = chan_val[cfg[2:0]];
            end
            if (nedge > 17) viol("more than 17 SCLK edges");
        end
    end

    always @(negedge sclk) begin
        tf = $realtime; t_fall = tf;
        #1;
        if (!cs_n) begin
            if (tf - t_rise < T_HI) viol("tHI: SCLK high time");
            if (nedge >= 6 && nedge <= 16) begin
                #(T_DO - 1);
                miso_r = (nedge == 6) ? 1'b0 : vsel[16 - nedge];   // null bit, then B9..B0
            end
        end
    end

    always @(mosi) begin
        #1;
        if (!cs_n && $realtime - 1 - t_rise < T_HD) viol("tHD: MOSI hold");
    end
endmodule
