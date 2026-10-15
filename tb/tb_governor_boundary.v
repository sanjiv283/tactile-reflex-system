`timescale 1ns / 1ps
// Threshold-boundary test for the safety governor, driven through reflex_top (Stage 1 interface).
// Expected behaviour was read from rtl/safety_governor.v, not assumed:
//   over-force : adc >= FORCE_MAX (900) sets;  adc < FORCE_RESUME (800) clears;  800..899 holds the state
//   range fault: adc >= ADC_FAULT_HI (1015) latches until reset (it is also >= 900, so over-force sets too)
//   fault_led = {estop, timeout, range, over};  tripped pulse = SAFE 1000 us
//   LUT pulse  = 2000 - 16*(adc>>4)  ->  899:1104  800:1200  799:1216  100:1904
module tb_governor_boundary;
    localparam T = 1000;                       // 1 MHz clock, as in tb_reflex_top
    reg clk = 0;
    always #(T/2) clk = ~clk;

    reg        rst_btn = 1, estop_btn = 0, grip_en_sw = 1;
    reg  [9:0] adc_value = 0;
    reg        adc_valid = 0;
    wire       servo_out, active_bank_led, dbg_cmd_toggle;
    wire [3:0] fault_led;

    reflex_top #(.CLK_HZ(1_000_000), .FRAME_US(2500)) dut (
        .clk(clk), .rst_btn(rst_btn), .estop_btn(estop_btn), .grip_en_sw(grip_en_sw),
        .adc_value(adc_value), .adc_valid(adc_valid),
        .lut_wr_en(1'b0), .lut_wr_addr(6'd0), .lut_wr_data(12'd0), .lut_swap(1'b0),
        .servo_out(servo_out), .fault_led(fault_led),
        .active_bank_led(active_bank_led), .dbg_cmd_toggle(dbg_cmd_toggle)
    );

    integer errors = 0;
    task expect(input [3:0] exp_fault, input integer exp_pulse, input [8*56-1:0] name);
        begin
            if (fault_led === exp_fault && dut.pulse_cmd === exp_pulse)
                $display("PASS  %0s: fault=%b pulse=%0d us", name, fault_led, dut.pulse_cmd);
            else begin
                $display("FAIL  %0s: fault=%b (exp %b) pulse=%0d us (exp %0d)",
                         name, fault_led, exp_fault, dut.pulse_cmd, exp_pulse);
                errors = errors + 1;
            end
        end
    endtask

    // one ADC sample, then let it propagate (valid -> lut -> governor: 2 clocks, plus margin)
    task sample(input [9:0] v);
        begin
            @(negedge clk); adc_value = v; adc_valid = 1'b1;
            @(negedge clk); adc_valid = 1'b0;
            repeat (4) @(negedge clk);
        end
    endtask
    task do_reset;
        begin
            @(negedge clk) rst_btn = 1'b1; repeat (5) @(negedge clk);
            rst_btn = 1'b0; repeat (4) @(negedge clk);
        end
    endtask

    initial begin
        repeat (10) @(negedge clk);
        rst_btn = 1'b0; repeat (4) @(negedge clk);

        // ---- over-force trip point: 899 / 900
        do_reset; sample(899); expect(4'b0000, 1104, "899: below FORCE_MAX, no trip");
        sample(900);           expect(4'b0001, 1000, "900: FORCE_MAX trips (>=), gripper open");

        // ---- over-force release point: 799 / 800, with the hold band in between
        do_reset; sample(900); expect(4'b0001, 1000, "re-trip at 900");
        sample(899);           expect(4'b0001, 1000, "899 after trip: held (hysteresis)");
        sample(801);           expect(4'b0001, 1000, "801 after trip: held");
        sample(800);           expect(4'b0001, 1000, "800: FORCE_RESUME not reached (needs <800), held");
        sample(799);           expect(4'b0000, 1216, "799: released, LUT command resumes");
        do_reset; sample(800); expect(4'b0000, 1200, "800 from clear state: no trip (hold band)");
        sample(799);           expect(4'b0000, 1216, "799 from clear state: normal");

        // ---- range fault: 1014 / 1015
        do_reset; sample(1014); expect(4'b0001, 1000, "1014: over-force only, no range fault");
        sample(100);            expect(4'b0000, 1904, "1014 did not latch: back to normal at 100");
        do_reset; sample(1015); expect(4'b0011, 1000, "1015: range fault (>=) + over-force");
        sample(100);            expect(4'b0010, 1000, "range fault latched, over-force released");
        sample(1023);           expect(4'b0011, 1000, "1023: both set again");
        do_reset;               expect(4'b0000, 1000, "reset clears range fault, open until first sample");
        sample(100);            expect(4'b0000, 1904, "normal operation after reset");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #20_000_000; $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
