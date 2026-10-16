`timescale 1ns / 1ps
// What an init file can do to the servo command, with the real reflex_top (lut_engine -> safety_governor -> servo_pwm).
// run_sim.sh writes FILE into a temporary directory and selects the mode:
//   MODE 0  FILE holds 64 words, some out of range (000, fff, 3e7=999, 7d1=2001, 3e8=1000, 7d0=2000, rest 5dc=1500).
//           Portable guarantee under test: whatever the table holds, the governor output stays inside 1000..2000 us.
//   MODE 1  FILE holds only NEXP words (NEXP < 64; 0 = file does not exist), all 5dc = 1500 us.
//           CHARACTERISATION of four-state simulation only: entries the file does not provide are unknown (x), the x
//           reaches the governor output and servo_out; an active fault, e-stop or reset then replaces it with the
//           SAFE value. Real FPGA memory has no x: what an unprovided entry holds there is tool-dependent (not tested).
// EVERY-CLOCK SERVO MONITOR (added in Stage 6C.1). servo_out is sampled at every falling clock edge (the DUT only
// changes at rising edges, so there is no race) and checked against a contract that depends on the phase of the test:
//   phase 1  KNOWN : servo_out is 0/1 every clock; every completed high pulse is 1000..2000 clocks (= us at 1 MHz)
//   phase 2  X-OK  : MODE 1 only - an unknown (x) servo_out is allowed (simulation characterisation, see above)
//   phase 3  SAFE  : servo_out is 0/1 every clock; every completed pulse is exactly 1000 us (the SAFE value)
//   always         : no high run longer than 2000 clocks; servo_out is 0 on every clock after a clock with internal reset
//                    asserted (a pulse cut short by such a reset is not counted as a pulse). Phase 3 starts 2 frames after the fault, because the servo only latches its command at a
//                    frame boundary (so the old command may legitimately still be on the wire for up to 2 frames).
// Each phase must have monitored cycles (and, where pulses are expected, completed pulses): see the end of the test.
// What this does NOT prove: what a real FPGA memory or output pin holds at power-up (four-state simulation only).
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


    // ---- every-clock servo monitor (see the header). phase is changed only at rising edges (set_phase), sampled at falling edges.
    integer phase = 0;
    integer cyc [0:3], unk [0:3], npulse [0:3], badw [0:3];
    integer run = 0, mw, long_run = 0, rst_cyc = 0, rst_viol = 0, k_init;
    reg     run_valid = 0, prev0 = 0, rst_prev = 0;
    initial for (k_init = 0; k_init < 4; k_init = k_init + 1) begin cyc[k_init] = 0; unk[k_init] = 0; npulse[k_init] = 0; badw[k_init] = 0; end
    task set_phase(input integer p); begin @(posedge clk); phase = p; end endtask
    always @(negedge clk) if (armed) begin
        if (rst_prev) begin rst_cyc = rst_cyc + 1; if (servo_out !== 1'b0) rst_viol = rst_viol + 1; end
        rst_prev = dut.rst;
        if (phase != 0) cyc[phase] = cyc[phase] + 1;
        if (servo_out !== 1'b0 && servo_out !== 1'b1) begin            // x or z
            if (phase != 0) unk[phase] = unk[phase] + 1;
            run = 0; run_valid = 0; prev0 = 0;
        end else if (servo_out === 1'b1) begin
            if (run == 0 && prev0) run_valid = 1;                         // rising edge seen after a known 0
            run = run + 1;
            if (run > 2000) long_run = long_run + 1;
            prev0 = 0;
        end else begin
            if (run > 0 && run_valid && phase != 0 && !rst_prev) begin   // a complete, fully observed pulse (a pulse cut off by reset is not counted)
                mw = run; npulse[phase] = npulse[phase] + 1;
                if (phase == 1 && !(mw >= 1000 && mw <= 2000)) badw[phase] = badw[phase] + 1;
                if (phase == 3 && mw != 1000)                  badw[phase] = badw[phase] + 1;
            end
            run = 0; run_valid = 0; prev0 = 1;
        end
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
            bad = 0; oob = 0; samp_en = 1; set_phase(1);
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
            do_reset; nclk(6000);                   // a reset in the middle of normal operation: servo_out low, then 2000 us pulses again
            check(last_w == 2000, "after a reset, the first pulses again equal the clamped table word (2000 us)");
            @(posedge clk); #1;
            check(unk[1] == 0 && badw[1] == 0 && long_run == 0, "every clock: servo_out known, every pulse 1000..2000 us, none longer than 2000");
            check(cyc[1] > 57 * 250 + 14000 && npulse[1] >= 10, "monitor ran: >28000 clocks and >=10 complete pulses observed (not vacuous)");
            check(rst_viol == 0 && rst_cyc >= 4, "servo_out is 0 on every clock after an internal reset clock (>=4 such clocks seen)");
            $display("INFO  monitor: phase1 clocks=%0d pulses=%0d unknown=%0d bad_width=%0d long_run=%0d reset_clocks=%0d", cyc[1], npulse[1], unk[1], badw[1], long_run, rst_cyc);
        end else begin
            samp_en = 1; set_phase(1);
            // ---- entries the file provides work normally
            if (NEXP > 0) begin
                bad = 0;
                for (i = 0; i < NEXP; i = i + 1) begin adc_value = 16 * i + 3; nclk(250); if (cmd !== 12'd1500) bad = bad + 1; end
                check(bad == 0, "entries present in the file: governor output 1500 us");
            end
            // ---- the first entry the file does not provide: unknown reaches the governor output and the servo (4-state sim)
            set_phase(2);
            adc_value = 16 * NEXP + 3; nclk(250);
            check((^cmd) === 1'bx, "SIM CHARACTERISATION: unprovided entry -> governor output unknown (x)");
            nclk(6000);
            check(x_seen == 1, "SIM CHARACTERISATION: the unknown reaches servo_out");
            // ---- an e-stop replaces it with the SAFE value, even while the unknown entry keeps being sampled
            estop_btn = 1; nclk(8);
            check(cmd === 12'd1000, "e-stop while the unknown entry is sampled: governor output = SAFE 1000, not x");
            nclk(2 * 2500 + 192);                    // the servo latches once per 2500-clock frame: wait 2 frames before demanding SAFE on the pin
            set_phase(3); nclk(5000);                // from here every pulse on servo_out must be exactly 1000 us and never x
            check(cmd === 12'd1000, "e-stop still held, unknown entry still sampled: governor output stays SAFE 1000");
            estop_btn = 0;
            // ---- reset: SAFE until the first sample, whatever was latched before
            samp_en = 0; do_reset;
            check(cmd === 12'd1000 && fault_led === 4'b0000, "after reset (no sample yet): governor output = SAFE 1000, faults cleared");
            // ---- an over-force sample that lands on an unprovided entry: the fault wins, x never latches
            adc_value = 950; samp_en = 1; nclk(250);
            check(cmd === 12'd1000 && fault_led[0] === 1'b1, "over-force sample on an unprovided entry: SAFE 1000 and over-force fault, not x");
            nclk(5750);                              // >2 frames after the reset: complete pulses must all be SAFE and known (phase 3)
            samp_en = 0; do_reset;
            // ---- recovery with an entry the file provides
            if (NEXP > 0) begin
                set_phase(1);
                adc_value = 3; samp_en = 1; nclk(250);
                check(cmd === 12'd1500, "after reset: an entry present in the file works again (1500 us)");
                nclk(5750);
                check(last_w == 1500, "after reset: the servo pulse for a table word present in the file is 1500 us");
            end
            set_phase(0);
            @(posedge clk); #1;
            check(unk[1] == 0 && unk[3] == 0 && badw[3] == 0 && badw[1] == 0 && long_run == 0, "every clock: known and exactly 1000 us after the fault (phase 3); 1000..2000 us before/after (phase 1)");
            check(cyc[3] >= 10000 && npulse[3] >= 4, "monitor ran: >=10000 clocks and >=4 complete SAFE pulses in phase 3 (not vacuous)");
            check(cyc[2] > 0 && (NEXP == 0 || cyc[1] > 0), "every phase monitored at least one clock");
            check(rst_viol == 0 && rst_cyc >= 10, "servo_out is 0 on every clock after an internal reset clock (>=10 such clocks over 3 resets)");
            $display("INFO  monitor: clocks p1=%0d p2=%0d p3=%0d; pulses p1=%0d p3=%0d; unknown clocks p1=%0d p2=%0d p3=%0d (p2 may be x); bad widths p1=%0d p3=%0d; reset clocks=%0d",
                     cyc[1], cyc[2], cyc[3], npulse[1], npulse[3], unk[1], unk[2], unk[3], badw[1], badw[3], rst_cyc);
        end

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
endmodule
