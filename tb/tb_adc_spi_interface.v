`timescale 1ns / 1ps
// Self-checking testbench: adc_spi_interface + behavioural MCP3008 model.
// Defaults: 100 MHz clock, 1 MHz SCLK. Worst case (slow board clock, max SCLK):
//   iverilog -Ptb_adc_spi_interface.CLK_HZ=27000000 -Ptb_adc_spi_interface.SCLK_HZ=1350000 ...
module tb_adc_spi_interface;
    parameter CLK_HZ  = 100_000_000;
    parameter SCLK_HZ = 1_000_000;
    localparam real T         = 1.0e9 / CLK_HZ;
    localparam      HALF      = (CLK_HZ + 2*SCLK_HZ - 1) / (2*SCLK_HZ);
    localparam      CONV_CLKS = 35*HALF + 1;

    reg clk = 0;
    always #(T/2.0) clk = ~clk;

    reg        rst = 1, start = 0;
    reg  [2:0] channel = 0;
    wire       busy, data_valid, frame_err, cs_n, sclk, mosi, adc_dout;
    wire [9:0] data;
    wire [2:0] data_channel;

    // MISO: driven by the model, or left floating to emulate a broken wire.
    // pullup models the FPGA pin pull-up to be enabled in the board constraints.
    reg  adc_connected = 1;
    wire miso;
    assign miso = adc_connected ? adc_dout : 1'bz;
    pullup (miso);

    adc_spi_interface #(.CLK_HZ(CLK_HZ), .SCLK_HZ(SCLK_HZ)) dut (
        .clk(clk), .rst(rst), .start(start), .channel(channel),
        .busy(busy), .data(data), .data_channel(data_channel),
        .data_valid(data_valid), .frame_err(frame_err),
        .spi_cs_n(cs_n), .spi_sclk(sclk), .spi_mosi(mosi), .spi_miso(miso)
    );

    mcp3008_model u_adc (.cs_n(cs_n), .sclk(sclk), .din(mosi), .dout(adc_dout));

    integer errors = 0;
    task check(input cond, input [8*56-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask

    // Wait for the end of the current conversion; capture what the DUT reported.
    reg  [9:0] r_val;
    reg  [2:0] r_ch;
    reg        r_valid, r_err;
    integer    n;
    task wait_result;
        begin
            n = 0;
            while (!data_valid && !frame_err && n < 4*CONV_CLKS) begin
                @(posedge clk); n = n + 1;
            end
            r_valid = data_valid; r_err = frame_err; r_val = data; r_ch = data_channel;
            @(posedge clk);
            if (data_valid !== 1'b0) begin
                $display("FAIL  data_valid wider than one clock"); errors = errors + 1;
            end
        end
    endtask

    task convert(input [2:0] ch);
        begin
            while (busy) @(posedge clk);
            @(posedge clk); channel <= ch; start <= 1'b1;
            @(posedge clk); start <= 1'b0;
            wait_result;
        end
    endtask

    integer  i, got, conv0, period;
    reg      ok;
    reg [9:0] prev;
    realtime t_a, t_b;

    initial begin
        #(50_000_000);   // 50 ms watchdog
        $display("FAIL  global watchdog timeout");
        $display("=== DONE: watchdog ===");
        $finish;
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_adc_spi_interface);
        $display("INFO  CLK_HZ=%0d SCLK_HZ=%0d HALF=%0d -> real SCLK=%0d Hz",
                 CLK_HZ, SCLK_HZ, HALF, CLK_HZ / (2*HALF));

        // ---- 1. Reset: deterministic outputs, no SPI activity even with start held
        start = 1'b1;
        repeat (3) @(posedge clk);
        ok = 1;
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk);
            if (cs_n !== 1'b1 || sclk !== 1'b0 || mosi !== 1'b0 || busy !== 1'b1 ||
                data_valid !== 1'b0 || frame_err !== 1'b0 || data !== 10'd0) ok = 0;
        end
        check(ok, "reset: CS high, SCLK/MOSI low, busy=1, no data");
        check(u_adc.conversions == 0, "reset: no conversion while start held");
        start <= 1'b0; rst <= 1'b0;
        repeat (2*HALF) @(posedge clk);
        check(busy === 1'b0, "reset released: interface idle");

        // ---- 2. Known codes on channel 0
        u_adc.value[0] = 10'd0;   convert(0); check(r_valid && r_val == 10'd0,   "code 0 (min)");
        u_adc.value[0] = 10'd1023;convert(0); check(r_valid && r_val == 10'd1023,"code 1023 (max)");
        u_adc.value[0] = 10'h2AA; convert(0); check(r_valid && r_val == 10'h2AA, "code 0x2AA (1010101010)");
        u_adc.value[0] = 10'h155; convert(0); check(r_valid && r_val == 10'h155, "code 0x155 (0101010101)");
        u_adc.value[0] = 10'd512; convert(0); check(r_valid && r_val == 10'd512, "code 512 (mid-scale)");

        // ---- 3. All eight channels
        for (i = 0; i < 8; i = i + 1) u_adc.value[i] = 100*i + 7;
        ok = 1;
        for (i = 0; i < 8; i = i + 1) begin
            convert(i);
            if (!(r_valid && r_val == 100*i + 7 && r_ch == i && u_adc.last_channel == i)) begin
                ok = 0;
                $display("      ch%0d: got val=%0d ch=%0d (model saw ch%0d)", i, r_val, r_ch, u_adc.last_channel);
            end
        end
        check(ok, "8 channels: value, data_channel, channel sent");

        // ---- 4. Back-to-back (start held) + channel change mid-conversion
        u_adc.value[3] = 10'd333; u_adc.value[5] = 10'd555;
        while (busy) @(posedge clk);
        conv0 = u_adc.conversions;
        @(posedge clk); channel <= 3'd3; start <= 1'b1;
        @(negedge cs_n); channel <= 3'd5;          // must not affect this conversion
        got = 0; ok = 1; n = 0;
        while (got < 5 && n < 10*CONV_CLKS) begin
            @(posedge clk); n = n + 1;
            if (data_valid) begin
                if (got == 0) t_a = $realtime;
                if (got == 1) t_b = $realtime;
                if (got == 0 && !(data == 10'd333 && data_channel == 3'd3)) ok = 0;
                if (got >  0 && !(data == 10'd555 && data_channel == 3'd5)) ok = 0;
                got = got + 1;
            end
        end
        start <= 1'b0;
        check(ok && got == 5, "back-to-back: 5 results, channel latched per frame");
        period = $rtoi((t_b - t_a) / T + 0.5);
        $display("INFO  SIMULATED conversion period: %0d clocks = %0.2f us (%0.1f kS/s)",
                 period, (t_b - t_a) / 1000.0, 1.0e6 / (t_b - t_a));
        check(period == CONV_CLKS, "conversion period = 35*HALF+1 clocks");
        repeat (2*HALF) @(posedge clk);
        while (busy) @(posedge clk);
        check(u_adc.conversions == conv0 + 5, "back-to-back: no extra/overlapping frames");

        // ---- 5. start pulsed while busy is ignored
        conv0 = u_adc.conversions;
        @(posedge clk); start <= 1'b1;
        @(posedge clk); start <= 1'b0;
        repeat (10*HALF) @(posedge clk);
        @(posedge clk); start <= 1'b1;             // DUT is mid-frame here
        @(posedge clk); start <= 1'b0;
        got = 0;
        for (i = 0; i < 3*CONV_CLKS; i = i + 1) begin
            @(posedge clk); if (data_valid) got = got + 1;
        end
        check(got == 1 && u_adc.conversions == conv0 + 1, "start while busy ignored");

        // ---- 6. Reset in the middle of a conversion
        conv0 = u_adc.conversions;
        @(posedge clk); channel <= 3'd1; start <= 1'b1;
        @(posedge clk); start <= 1'b0;
        repeat (20*HALF) @(posedge clk);            // around rising edge 10
        rst <= 1'b1;
        @(posedge clk); @(posedge clk);
        check(cs_n === 1'b1 && sclk === 1'b0 && data_valid === 1'b0,
              "reset mid-frame: CS released, no data_valid");
        repeat (5) @(posedge clk); rst <= 1'b0;
        @(posedge clk);
        check(data === 10'd0, "reset clears data");
        check(u_adc.conversions == conv0, "aborted frame not completed");
        u_adc.value[1] = 10'd777;
        convert(1);
        check(r_valid && r_val == 10'd777 && r_ch == 3'd1, "first conversion after reset");

        // ---- 7. MISO disconnected (pull-up -> null bit reads 1)
        prev = data;
        adc_connected = 0;
        convert(2);
        check(!r_valid && r_err && data == prev, "MISO open: frame_err, no data_valid, data kept");
        adc_connected = 1;
        u_adc.value[2] = 10'd222;
        convert(2);
        check(r_valid && r_val == 10'd222, "recovers after MISO reconnected");

        // ---- 8. Datasheet timing seen by the model
        $display("INFO  shortest SCLK period seen: %0.1f ns (limit 740.7 ns)", u_adc.min_period);
        check(u_adc.violations == 0, "MCP3008 timing: tSUCS, tCSH, SCLK period, tSU, mode 0");
        check(u_adc.diff_requests == 0, "every request single-ended (SGL=1)");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
endmodule
