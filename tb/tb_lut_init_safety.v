`timescale 1ns / 1ps
// What an init file can do to the servo command, with the real reflex_top (lut_engine -> safety_governor -> servo_pwm).
// run_sim.sh writes FILE into a temporary directory and selects the mode:
//   MODE 0  FILE holds 64 words, some out of range (000, fff, 3e7=999, 7d1=2001, 3e8=1000, 7d0=2000, rest 5dc=1500).
//           Portable guarantee under test: whatever the table holds, the governor output stays inside 1000..2000 us.
//   MODE 1  FILE holds only NEXP words (NEXP < 64; 0 = file does not exist), all 5dc = 1500 us.
//           CHARACTERISATION of four-state simulation only: entries the file does not provide are unknown (x), the x
//           reaches the governor output and servo_out; an active fault, e-stop or reset then replaces it with the
//           SAFE value. Real FPGA memory has no x: what an unprovided entry holds there is tool-dependent (not tested).
module tb_lut_init_safety;
    parameter FILE = "";
    parameter MODE = 0;
    parameter NEXP = 0;

    reg clk = 0;
    always #500 clk = ~clk;                           // 1 MHz

    reg        rst_btn = 1, estop_btn = 0, grip_en_sw = 1;
    reg  [9:0] adc_value = 0;
    reg        adc_valid = 0, samp_en = 0;
    wire       servo_out, active_bank_led, dbg;
    wire [3:0] fault_led;

    reflex_top #(.CLK_HZ(1_000_000), .FRAME_US(2500), .LUT_INIT_FILE(FILE)) dut (
        .clk(clk), .rst_btn(rst_btn), .estop_btn(estop_btn), .grip_en_sw(grip_en_sw),
        .adc_value(adc_value), .adc_valid(adc_valid),
        .lut_wr_en(1'b0), .lut_wr_addr(6'd0), .lut_wr_data(12'd0), .lut_swap(1'b0),
        .servo_out(servo_out), .fault_led(fault_led), .active_bank_led(active_bank_led), .dbg_cmd_toggle(dbg));

    wire [11:0] cmd = dut.pulse_cmd;                  // governor output (what the servo generator latches)

    // an ADC sample every 100 clocks while samp_en (well inside the 1000-clock ADC timeout)
    integer cnt = 0;
    always @(negedge clk) begin
        cnt = cnt + 1;
        adc_valid = samp_en && (cnt % 100 == 0);
    end

    // servo pulse width in clocks (= us at 1 MHz); x_seen = servo_out was ever unknown after reset
    integer last_w = 0, w = 0;
    reg     prev = 0, x_seen = 0, armed = 0;   // armed: after the first reset (servo_out is x before the first clock)
    always @(posedge clk) begin
        if (armed && servo_out === 1'bx) x_seen <= 1;
        if (servo_out === 1'b1) w = w + 1;
        if (prev === 1'b1 && servo_out === 1'b0) last_w = w;
        if (servo_out !== 1'b1) w = 0;
        prev <= servo_out;
    end

    integer errors = 0;
    task check(input cond, input [8*112-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask
    task nclk(input integer n); repeat (n) @(negedge clk); endtask
    task do_reset; begin rst_btn = 1; nclk(6); rst_btn = 0; nclk(6); end endtask

    function integer expect_pulse(input integer i);
        begin
            case (i)
                0: expect_pulse = 1000;  // 000 -> clamped up
                1: expect_pulse = 2000;  // fff (4095) -> clamped down
                2: expect_pulse = 1000;  // 3e7 (999)
                3: expect_pulse = 2000;  // 7d1 (2001)
                4: expect_pulse = 1000;  // 3e8 (1000) exactly the limit
                5: expect_pulse = 2000;  // 7d0 (2000) exactly the limit
                default: expect_pulse = 1500;
            endcase
        end
    endfunction

    integer i, bad, oob;
    initial begin #400_000_000; $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end

    initial begin
        nclk(6); rst_btn = 0; nclk(6); armed = 1;

        if (MODE == 0) begin
            // ---- every entry through the whole top: governor output equals the clamped table word, within the limits at the sample points
            //      (one per entry, 250 clocks after the code change; NOT an every-clock monitor - the cycle-by-cycle clamp checks are
            //      in tb_governor_priority and tb_safety_vs_upload).
            //      Entries 0..56 only: ADC codes of entries 57..63 are at or above FORCE_MAX (900), where the governor goes SAFE.
            bad = 0; oob = 0; samp_en = 1;
            for (i = 0; i < 57; i = i + 1) begin
                adc_value = 16 * i + 3; nclk(250);
                if (cmd !== expect_pulse(i)) begin bad = bad + 1; if (bad < 5) $display("      entry %0d: governor output %0d, expected %0d", i, cmd, expect_pulse(i)); end
                if (!(cmd >= 1000 && cmd <= 2000)) oob = oob + 1;
            end
            check(bad == 0, "entries 0..56: governor output = table word clamped to 1000..2000");
            check(oob == 0, "governor output within 1000..2000 us at each of the 57 sample points (250 clocks after each change)");
            // ---- the servo pulse itself, for an entry clamped up (0 -> 1000) and one clamped down (1 -> 2000)
            adc_value = 3;   nclk(7000); check(last_w == 1000, "servo pulse for table word 000: 1000 us");
            adc_value = 19;  nclk(7000); check(last_w == 2000, "servo pulse for table word fff: 2000 us");
            check(x_seen == 0, "servo_out never unknown");
        end else begin
            samp_en = 1;
            // ---- entries the file provides work normally
            if (NEXP > 0) begin
                bad = 0;
                for (i = 0; i < NEXP; i = i + 1) begin adc_value = 16 * i + 3; nclk(250); if (cmd !== 12'd1500) bad = bad + 1; end
                check(bad == 0, "entries present in the file: governor output 1500 us");
            end
            // ---- the first entry the file does not provide: unknown reaches the governor output and the servo (4-state sim)
            adc_value = 16 * NEXP + 3; nclk(250);
            check((^cmd) === 1'bx, "SIM CHARACTERISATION: unprovided entry -> governor output unknown (x)");
            nclk(6000);
            check(x_seen == 1, "SIM CHARACTERISATION: the unknown reaches servo_out");
            // ---- an e-stop replaces it with the SAFE value, even while the unknown entry keeps being sampled
            estop_btn = 1; nclk(8);
            check(cmd === 12'd1000, "e-stop while the unknown entry is sampled: governor output = SAFE 1000, not x");
            estop_btn = 0;
            // ---- reset: SAFE until the first sample, whatever was latched before
            samp_en = 0; do_reset;
            check(cmd === 12'd1000 && fault_led === 4'b0000, "after reset (no sample yet): governor output = SAFE 1000, faults cleared");
            // ---- an over-force sample that lands on an unprovided entry: the fault wins, x never latches
            adc_value = 950; samp_en = 1; nclk(250);
            check(cmd === 12'd1000 && fault_led[0] === 1'b1, "over-force sample on an unprovided entry: SAFE 1000 and over-force fault, not x");
            samp_en = 0; do_reset;
            // ---- recovery with an entry the file provides
            if (NEXP > 0) begin
                adc_value = 3; samp_en = 1; nclk(250);
                check(cmd === 12'd1500, "after reset: an entry present in the file works again (1500 us)");
            end
        end

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
endmodule
