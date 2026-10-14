`timescale 1ns/1ps
// Stage 2 integration: mcp3008_model -> adc_spi_interface -> reflex_top (via reflex_top_spi).
// Real 100 MHz clock, 1 MHz SCLK, real 1000 us ADC timeout. Only shortcut: 2.5 ms servo frame.
module tb_reflex_top_spi;
    localparam real    TCLK   = 10.0;
    localparam integer HALF   = 50;
    localparam integer PERIOD = 35 * HALF + 1;     // 1751 clocks per conversion

    reg clk = 0, rst = 1, estop = 0;
    wire cs_n, sclk, mosi, miso, servo_pwm, dbg_cmd_toggle, safe_state, over_force;
    wire f_range, f_to, f_estop, ferr;
    wire [11:0] pulse_cmd;

    reflex_top_spi #(.CLK_HZ(100_000_000), .SCLK_HZ(1_000_000), .FRAME_US(2500)) dut (
        .clk(clk), .rst(rst), .estop(estop), .miso(miso), .cs_n(cs_n), .sclk(sclk), .mosi(mosi),
        .servo_pwm(servo_pwm), .pulse_cmd(pulse_cmd), .dbg_cmd_toggle(dbg_cmd_toggle),
        .safe_state(safe_state), .over_force(over_force), .fault_range(f_range),
        .fault_timeout(f_to), .fault_estop(f_estop), .adc_frame_err(ferr));
    mcp3008_model m (.cs_n(cs_n), .sclk(sclk), .mosi(mosi), .miso(miso));

    always #(TCLK / 2) clk = ~clk;

    integer errors = 0, i, n0;
    task chk(input c, input [255:0] msg);
        if (!c) begin errors = errors + 1; $display("FAIL @%0t: %0s", $time, msg); end
    endtask
    task tick(input integer n); repeat (n) @(negedge clk); endtask
    task set0(input [9:0] v); begin m.chan_val[0] = v; tick(2 * PERIOD + 20); end endtask

    // measure the servo pulse after a command change (first pulse may be stale, use the second)
    real t0;
    task pulse_us(output real us);
        begin @(posedge servo_pwm); t0 = $realtime; @(negedge servo_pwm); us = ($realtime - t0) / 1000.0; end
    endtask
    task check_pulse(input [9:0] v, input integer exp);
        real a, b;
        begin
            set0(v); pulse_us(a); pulse_us(b);
            chk(b > exp - 0.01 && b < exp + 0.01, "servo pulse width from SPI force reading");
            chk(pulse_cmd == exp, "pulse_cmd from SPI force reading");
            if (!(b > exp - 0.01 && b < exp + 0.01)) $display("  adc=%0d expected %0d us got %0f us", v, exp, b);
        end
    endtask

    // logs
    integer ncs = 0, nrise = 0;
    real cs_t [0:63];
    real t_csr, t_tog, t_lastvalid;
    always @(negedge cs_n) begin cs_t[ncs % 64] = $realtime; ncs = ncs + 1; end
    always @(posedge cs_n) begin t_csr = $realtime; nrise = nrise + 1; end
    always @(dbg_cmd_toggle) t_tog = $realtime;

    task do_reset; begin rst = 1; tick(5); rst = 0; end endtask
    task at_frame_boundary; begin @(posedge cs_n); tick(2); end endtask   // CS high, next frame >= 50 clocks away

    real per, lat, w;
    integer samples;
    reg [9:0] vals [0:4];

    initial begin
        for (i = 0; i < 8; i = i + 1) m.chan_val[i] = 999;       // other channels must never be used
        m.chan_val[0] = 0;

        // ---- reset: no SPI activity, no servo pulses
        tick(30);
        chk(cs_n === 1 && sclk === 0 && mosi === 0, "reset: SPI idle");
        chk(servo_pwm === 0, "reset: no servo pulse");
        chk(ncs == 0 && pulse_cmd == 2000, "reset: no frames, SAFE command");
        rst = 0;

        // ---- force readings via SPI -> servo pulse
        check_pulse(0, 2000); check_pulse(320, 1680); check_pulse(640, 1360); check_pulse(880, 1120);
        chk(m.ch_mask == 8'h01, "only channel 0 was read");

        // ---- over-force with hysteresis
        set0(950); chk(over_force && pulse_cmd == 2000, "950 over-force -> open");
        set0(850); chk(over_force && pulse_cmd == 2000, "850 still open (hysteresis)");
        set0(700); chk(!over_force && pulse_cmd == 1300, "700 resumes");

        // ---- sample period
        for (i = ncs - 6; i < ncs - 1; i = i + 1) begin
            per = (cs_t[(i + 1) % 64] - cs_t[i % 64]) / TCLK;
            chk(per > PERIOD - 0.01 && per < PERIOD + 0.01, "sample period != 1751 clocks");
        end

        // ---- latency: ADC CS rising edge -> dbg_cmd_toggle (value changes between frames)
        vals[0] = 100; vals[1] = 250; vals[2] = 400; vals[3] = 150; vals[4] = 500;
        for (i = 0; i < 5; i = i + 1) begin
            at_frame_boundary; m.chan_val[0] = vals[i];       // takes effect in the next frame
            @(posedge cs_n); tick(6);                          // next frame delivered, toggle settled
            lat = (t_tog - t_csr) / TCLK;
            chk(lat == 2.0, "CS rise -> dbg_cmd_toggle != 2 clocks");
            if (i == 0) $display("INFO: CS rise -> dbg_cmd_toggle = %0.1f clocks (simulated)", lat);
        end

        // ---- healthy run: no timeout, enough samples
        n0 = nrise; tick(500_000);                              // 5 ms
        samples = nrise - n0;
        $display("INFO: %0d conversions in 5 ms", samples);
        chk(samples >= 5000000 / (PERIOD * 10) - 1, "too few samples in 5 ms");
        chk(!f_to && !safe_state, "healthy run: no timeout");

        // ---- MISO disconnected at a frame boundary: frame_err, no valid data, timeout trips
        m.chan_val[0] = 300; tick(2 * PERIOD);
        at_frame_boundary; t_lastvalid = t_csr; m.disconnect = 1;     // last valid frame completed at t_csr
        wait (f_to);
        w = ($realtime - t_lastvalid) / 1000.0;
        $display("INFO: timeout %0f us after last valid sample (frame_err frames running)", w);
        chk(w > 999.5 && w < 1001.5, "timeout ~1000 us after last valid sample");
        chk(ferr !== 1'bx, "frame_err defined");
        tick(5); chk(pulse_cmd == 2000 && safe_state, "timeout -> servo open");
        at_frame_boundary; m.disconnect = 0; tick(4 * PERIOD);
        chk(f_to && pulse_cmd == 2000, "timeout latched after reconnect");
        do_reset; tick(3 * PERIOD);
        chk(!f_to && pulse_cmd == 1700, "reset recovers (300 -> 1700 us)");

        // ---- range fault through the SPI path
        m.chan_val[0] = 1020; tick(2 * PERIOD);
        chk(f_range && pulse_cmd == 2000, "1020 range fault -> SAFE");
        m.chan_val[0] = 100; tick(2 * PERIOD); chk(f_range && pulse_cmd == 2000, "range fault latched");
        do_reset; tick(3 * PERIOD); chk(!f_range && pulse_cmd == 1900, "reset clears range fault");

        // ---- e-stop through the full path
        @(negedge clk); estop = 1; tick(2); estop = 0; tick(3);
        chk(f_estop && pulse_cmd == 2000, "e-stop -> SAFE");
        tick(3 * PERIOD); chk(f_estop && pulse_cmd == 2000, "e-stop latched");
        do_reset; tick(3 * PERIOD); chk(!f_estop && pulse_cmd == 1900, "reset clears e-stop");

        // ---- datasheet timing over the whole run
        chk(m.violations == 0, "datasheet timing violations in model");
        chk(m.ch_mask == 8'h01, "channels other than 0 were requested");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #400_000_000; $display("FAIL: global timeout"); $finish; end
endmodule
