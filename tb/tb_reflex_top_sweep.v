`timescale 1ns / 1ps
// Exhaustive / randomised tests of the Stage 1 reflex path (reflex_top = LUT + safety governor), checked against a
// small reference model written from the documented behaviour:
//   command = SAFE (1000 us) when over-force is active or a range fault is latched or grip is off;
//   otherwise 2000 - 16*(adc>>4);
//   over-force sets at adc >= 900 and clears at adc < 800 (800..899 holds); range fault latches at adc >= 1015.
// 1 MHz clock (1000 clocks = the 1000 us ADC timeout), so samples are kept less than 1000 clocks apart.
module tb_reflex_top_sweep;
    reg clk = 0;
    always #500 clk = ~clk;

    reg        rst_btn = 1, estop_btn = 0, grip_en_sw = 1;
    reg  [9:0] adc_value = 0;
    reg        adc_valid = 0;
    wire       servo_out, active_bank_led, dbg_cmd_toggle;
    wire [3:0] fault_led;

    reflex_top #(.CLK_HZ(1_000_000), .FRAME_US(2500)) dut (
        .clk(clk), .rst_btn(rst_btn), .estop_btn(estop_btn), .grip_en_sw(grip_en_sw),
        .adc_value(adc_value), .adc_valid(adc_valid),
        .lut_wr_en(1'b0), .lut_wr_addr(6'd0), .lut_wr_data(12'd0), .lut_swap(1'b0),
        .servo_out(servo_out), .fault_led(fault_led), .active_bank_led(active_bank_led),
        .dbg_cmd_toggle(dbg_cmd_toggle));
    wire [11:0] cmd = dut.pulse_cmd;

    integer errors = 0;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask
    task nclk(input integer n); repeat (n) @(negedge clk); endtask
    task do_reset; begin @(negedge clk); rst_btn = 1; nclk(6); rst_btn = 0; nclk(4); end endtask

    // ---- reference model
    reg m_over, m_range;
    task m_reset; begin m_over = 0; m_range = 0; end endtask
    task m_step(input [9:0] code);
        begin
            if (code >= 10'd1015) m_range = 1;
            if (code >= 10'd900) m_over = 1; else if (code < 10'd800) m_over = 0;
        end
    endtask
    function [11:0] m_cmd(input [9:0] code);
        begin m_cmd = (m_over || m_range) ? 12'd1000 : (12'd2000 - 12'd16 * (code >> 4)); end
    endfunction
    function [3:0] m_fault(input dummy); begin m_fault = {2'b00, m_range, m_over}; end endfunction

    task sample(input [9:0] code);                 // one isolated sample, result settled
        begin @(negedge clk); adc_value = code; adc_valid = 1; @(negedge clk); adc_valid = 0; nclk(4); end
    endtask

    integer k, bad, first_bad, bad_f;
    reg [9:0] code;

    // ---- portable xorshift generator (same sequence on every simulator)
    reg [31:0] rs;
    task rnd; begin rs = rs ^ (rs << 13); rs = rs ^ (rs >> 17); rs = rs ^ (rs << 5); end endtask

    reg [11:0] rd [0:4095];
    reg [9:0]  cd [0:4095];
    reg [11:0] ex [0:4095];
    reg [3:0]  ef [0:4095];
    reg [3:0]  rf [0:4095];

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_reflex_top_sweep);
        nclk(8); rst_btn = 0; nclk(6);

        // ---- A. every ADC code 0..1023, rising
        m_reset; bad = 0; bad_f = 0; first_bad = -1;
        for (k = 0; k < 1024; k = k + 1) begin
            sample(k[9:0]); m_step(k[9:0]);
            if (cmd !== m_cmd(k[9:0])) begin bad = bad + 1; if (first_bad < 0) first_bad = k; end
            if (fault_led !== m_fault(0)) bad_f = bad_f + 1;
        end
        if (bad) $display("      first mismatch at code %0d: cmd=%0d expected=%0d", first_bad, cmd, m_cmd(10'd1023));
        check(bad == 0, "sweep up, all 1024 codes: command = LUT value below 900, SAFE from 900 (exact for every code)");
        check(bad_f == 0, "sweep up: fault bits follow the model for every code (over-force from 900, range fault from 1015)");

        // ---- B. falling from a trip: hold band 800..949 stays SAFE, release below 800
        do_reset; m_reset; bad = 0; bad_f = 0;
        sample(10'd950); m_step(10'd950);
        for (k = 949; k >= 0; k = k - 1) begin
            sample(k[9:0]); m_step(k[9:0]);
            if (cmd !== m_cmd(k[9:0])) bad = bad + 1;
            if (fault_led !== m_fault(0)) bad_f = bad_f + 1;
        end
        check(bad == 0, "sweep down from a trip, codes 949..0: SAFE until 799, then the LUT value (hysteresis for every code)");
        check(bad_f == 0, "sweep down: over-force bit clears exactly below 800");

        // ---- C. randomised samples against the model (range fault ends a run: reset and continue)
        rs = 32'h1BADB002; do_reset; m_reset; bad = 0; bad_f = 0; first_bad = -1;
        for (k = 0; k < 2500; k = k + 1) begin
            rnd;
            code = (rs[3:0] == 4'd0) ? (10'd1015 + rs[13:8] % 9) :               // occasional range-fault code
                   (rs[5:4] == 2'd0) ? (10'd780 + rs[15:8] % 160) :              // concentrate on the 780..939 band
                   rs[25:16];
            if (code > 10'd1023) code = 10'd1023;
            sample(code); m_step(code);
            if (cmd !== m_cmd(code)) begin bad = bad + 1; if (first_bad < 0) first_bad = k; end
            if (fault_led !== m_fault(0)) bad_f = bad_f + 1;
            if (m_range) begin do_reset; m_reset; end
        end
        if (bad) $display("      first random mismatch at sample %0d", first_bad);
        check(bad == 0 && bad_f == 0, "2500 pseudo-random samples (heavy around the thresholds): command and faults match the model every time");

        // ---- D. samples on consecutive clocks (adc_valid high for every clock), result checked sample by sample
        do_reset; m_reset;
        for (k = 0; k < 400; k = k + 1) begin           // ramp 700..899, then jump, then down through the band
            if (k < 200) cd[k] = 700 + k;
            else if (k < 260) cd[k] = 900 + (k - 200);         // 900..959 : trip and stay tripped
            else cd[k] = 959 - (k - 260);                       // 959 down to 820, then past 800
        end
        for (k = 0; k < 400; k = k + 1) begin m_step(cd[k]); ex[k] = m_cmd(cd[k]); ef[k] = m_fault(0); end
        for (k = 0; k < 404; k = k + 1) begin
            @(negedge clk);
            rd[k] = cmd; rf[k] = fault_led;                       // value visible before this clock's new sample
            if (k < 400) begin adc_value = cd[k]; adc_valid = 1; end else adc_valid = 0;
        end
        bad = 0; bad_f = 0; first_bad = -1;
        for (k = 0; k < 400; k = k + 1) begin
            if (rd[k + 2] !== ex[k]) begin bad = bad + 1; if (first_bad < 0) first_bad = k; end
            if (rf[k + 1] !== ef[k]) bad_f = bad_f + 1;
        end
        if (bad) $display("      first back-to-back mismatch at sample %0d: got %0d expected %0d", first_bad, rd[first_bad+2], ex[first_bad]);
        check(bad == 0, "400 samples on consecutive clocks: each sample's command appears exactly 2 clocks later, in order");
        check(bad_f == 0, "400 consecutive-clock samples: fault bits update one clock after each sample");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #400_000_000; $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
