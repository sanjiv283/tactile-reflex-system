`timescale 1ns / 1ps
// Safety versus LUT upload, on the full Stage 4 top (reflex_top_uart + MCP3008 model), real RTL end to end:
//   * a latched safety fault (e-stop, over-force, ADC timeout) is never weakened by an upload or a COMMIT: the servo
//     command stays SAFE the whole time even though the upload commits (COMMITTED is reported) and the LUT swaps;
//   * the table committed during a fault is the one used once the fault clears (nothing stale, nothing lost);
//   * failed uploads (partial, invalid entry, ABORT, timeout) change neither the live table nor the servo command;
//   * a monitor on EVERY clock of the run asserts the output is always inside the servo limits and equal to SAFE
//     whenever a fault bit has been set for three clocks.
// 100 MHz, 2 Mbaud, 200 us upload timeout (simulation speed only), servo frame 2.5 ms.
// Tables: default O(i)=2000-16*i (force 640 -> 1360); N(i)=1900-10*i (force 640 -> 1500); B(i)=1800-5*i (-> 1600).
module tb_safety_vs_upload;
    parameter FRAME_US = 2500;
    parameter WATCHDOG_NS = 400_000_000;
    localparam CLK_HZ = 100_000_000, BAUD = 2_000_000;
    localparam real T = 10.0, BIT_NS = 500.0;
    localparam CONV_CLKS = 1751;

    reg clk = 0;
    always #(T/2) clk = ~clk;

    reg  rst_btn = 1, estop_btn = 0, grip_en_sw = 0, uart_rxd = 1;
    wire cs_n, sclk, mosi, adc_dout, servo_out, active_bank_led, dbg_cmd_toggle, adc_ferr;
    wire [3:0] fault_led, upload_err;
    wire upload_ack, upload_nak, upload_active, upload_failed, upload_commit;
    wire [6:0] upload_entries;
    wire uart_txd, tx_busy, resp_overflow;

    reg  adc_connected = 1;
    tri1 miso;
    assign miso = adc_connected ? adc_dout : 1'bz;

    reflex_top_uart #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .UPLOAD_TIMEOUT_US(200), .SCLK_HZ(1_000_000),
                      .FRAME_US(FRAME_US), .RESP_FIFO_DEPTH(4)) dut (
        .clk(clk), .rst_btn(rst_btn), .estop_btn(estop_btn), .grip_en_sw(grip_en_sw), .uart_rxd(uart_rxd),
        .spi_cs_n(cs_n), .spi_sclk(sclk), .spi_mosi(mosi), .spi_miso(miso),
        .servo_out(servo_out), .fault_led(fault_led), .active_bank_led(active_bank_led),
        .dbg_cmd_toggle(dbg_cmd_toggle), .adc_frame_err(adc_ferr),
        .upload_ack(upload_ack), .upload_nak(upload_nak), .upload_err(upload_err),
        .upload_active(upload_active), .upload_failed(upload_failed),
        .upload_entries(upload_entries), .upload_commit(upload_commit),
        .uart_txd(uart_txd), .tx_busy(tx_busy), .resp_overflow(resp_overflow));
    mcp3008_model u_adc (.cs_n(cs_n), .sclk(sclk), .din(mosi), .dout(adc_dout));

    // declared before task check, which prints it (Icarus 13 reported 'Unable to bind' when these followed the task)
    wire [11:0] pulse_cmd = dut.u_spi.u_core.pulse_cmd;

    integer errors = 0;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s  (fault=%b cmd=%0d bank=%b)", name, fault_led, pulse_cmd, active_bank_led); errors = errors + 1; end
        end
    endtask
    task ticks(input integer n); repeat (n) @(posedge clk); endtask

    // ---------------- always-on invariant monitor
    integer streak = 0, viol_range = 0, viol_safe = 0, cmd_changes = 0, seen1500 = 0;
    reg [11:0] prev_cmd = 12'd1000;
    reg mon_en = 0;
    always @(posedge clk) if (mon_en) begin
        if (pulse_cmd < 1000 || pulse_cmd > 2000) viol_range = viol_range + 1;
        if (fault_led !== 4'b0000) streak = streak + 1; else streak = 0;
        if (streak >= 3 && pulse_cmd !== 12'd1000) viol_safe = viol_safe + 1;
        if (pulse_cmd !== prev_cmd) cmd_changes = cmd_changes + 1;
        prev_cmd = pulse_cmd;
        if (pulse_cmd === 12'd1500) seen1500 = seen1500 + 1;
    end
    integer n_wr = 0, n_swap = 0, n_commit = 0;
    always @(posedge clk) begin
        if (dut.wr_en) n_wr = n_wr + 1;
        if (dut.swap) n_swap = n_swap + 1;
        if (upload_commit) n_commit = n_commit + 1;
    end

    // ---------------- host side
    task uart_byte(input [7:0] b);
        integer k;
        begin
            uart_rxd = 0; #(BIT_NS);
            for (k = 0; k < 8; k = k + 1) begin uart_rxd = b[k]; #(BIT_NS); end
            uart_rxd = 1; #(BIT_NS);
        end
    endtask
    task pkt0(input [7:0] cmd); begin uart_byte(8'hA5); uart_byte(cmd); uart_byte(cmd); end endtask
    task pkt_write(input [5:0] a, input [11:0] v);
        reg [7:0] h, l;
        begin
            h = {4'h0, v[11:8]}; l = v[7:0];
            uart_byte(8'hA5); uart_byte(8'h02); uart_byte({2'b00, a}); uart_byte(h); uart_byte(l); uart_byte(8'h02 ^ {2'b00, a} ^ h ^ l);
        end
    endtask
    function [11:0] tv(input integer which, input integer i);
        tv = (which == 1) ? (1900 - 10 * i) : (1800 - 5 * i);
    endfunction
    // BEGIN + 64 WRITEs (skipping `skip`, entry `bad_at` replaced by an out-of-range value) + optional COMMIT, no waiting
    task upload(input integer which, input integer skip, input integer bad_at, input do_commit);
        integer k, a;
        begin
            pkt0(8'h01);
            for (k = 0; k < 64; k = k + 1) begin
                a = (k * 29 + 3) % 64;
                if (a == bad_at) pkt_write(a[5:0], 12'd5);
                else if (a != skip) pkt_write(a[5:0], tv(which, a));
            end
            if (do_commit) pkt0(8'h03);
        end
    endtask

    wire [7:0] mdata; wire mvalid; wire [31:0] mn, mfe;
    uart_monitor #(.BIT_NS(BIT_NS)) mon (.rx(uart_txd), .data(mdata), .valid(mvalid), .n_bytes(mn), .n_fe(mfe));
    reg [1:0] pst = 0; reg [7:0] p_st, p_info;
    integer n_good = 0, n_bad = 0;
    reg [7:0] last_st, last_info;
    function frame_ok(input [7:0] st, input [7:0] info);
        reg [7:0] b;
        begin b = st & 8'h7F;
              frame_ok = (b == 8'h06 && info <= 64) || (b == 8'h07 && info == 64) || (b == 8'h15 && info >= 1 && info <= 10); end
    endfunction
    always @(posedge mvalid) begin : parser
        reg [7:0] b; b = mdata;
        case (pst)
            2'd0: if (b == 8'h5A) pst = 1;
            2'd1: if (b == 8'h5A) pst = 1; else begin p_st = b; pst = 2; end
            2'd2: if (b == 8'h5A) pst = 1; else begin p_info = b; pst = 3; end
            2'd3: if (b == 8'h5A) pst = 1;
                  else begin
                      if (b == (p_st ^ p_info) && frame_ok(p_st, p_info)) begin last_st = p_st; last_info = p_info; n_good = n_good + 1; end
                      else n_bad = n_bad + 1;
                      pst = 0;
                  end
        endcase
    end
    task wait_frames(input integer target, input integer max_clks);       // wait until n_good >= target
        integer w; begin w = 0; while (n_good < target && w < max_clks) begin @(posedge clk); w = w + 1; end end
    endtask
    task do_reset; begin @(posedge clk) rst_btn = 1; ticks(6); rst_btn = 0; ticks(2 * CONV_CLKS + 200); end endtask
    task settle_samples; begin ticks(2 * CONV_CLKS + 100); end endtask

    integer g0, s0, c0, w0, bank0, i;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_safety_vs_upload);
        for (i = 0; i < 8; i = i + 1) u_adc.value[i] = 10'd999;
        u_adc.value[0] = 10'd640;
        ticks(40); rst_btn = 0; grip_en_sw = 1; settle_samples;
        mon_en = 1;
        check(pulse_cmd == 1360 && fault_led == 4'b0000, "baseline: force 640 -> 1360 us (default table), no fault");

        // ===== S1: e-stop latched, then a full upload + COMMIT
        @(posedge clk) estop_btn = 1; ticks(6); estop_btn = 0; ticks(200);
        check(fault_led[3] === 1'b1 && pulse_cmd == 1000, "e-stop latched: SAFE");
        g0 = n_good; s0 = n_swap; c0 = n_commit; bank0 = active_bank_led;
        upload(1, -1, -1, 1);
        wait_frames(g0 + 66, 2_000_000); ticks(500);
        check(n_good == g0 + 66 && last_st === 8'h07 && last_info === 8'd64 && n_bad == 0, "upload during e-stop: 66 responses, the last one COMMITTED(64)");
        check(n_swap == s0 + 1 && n_commit == c0 + 1 && active_bank_led != bank0, "COMMIT during e-stop really swapped the LUT (one swap, bank LED toggled)");
        check(fault_led[3] === 1'b1 && pulse_cmd == 1000 && viol_safe == 0, "...but the e-stop still holds the servo command at SAFE (upload cannot weaken a fault)");
        do_reset;
        check(fault_led == 4'b0000 && pulse_cmd == 1500, "reset clears the e-stop; the table committed during the fault is live: force 640 -> 1500 us");

        // ===== S2: over-force active during an upload + COMMIT
        u_adc.value[0] = 10'd950; settle_samples;
        check(fault_led[0] === 1'b1 && pulse_cmd == 1000, "force 950: over-force, SAFE");
        g0 = n_good; s0 = n_swap; bank0 = active_bank_led;
        upload(2, -1, -1, 1);
        wait_frames(g0 + 66, 2_000_000); ticks(500);
        check(last_st === 8'h07 && n_swap == s0 + 1 && active_bank_led != bank0, "COMMIT during over-force: COMMITTED reported and the swap happened");
        check(pulse_cmd == 1000 && fault_led[0] === 1'b1, "...servo command stayed SAFE through the swap while force was high");
        seen1500 = 0;
        u_adc.value[0] = 10'd640; settle_samples;
        check(fault_led == 4'b0000 && pulse_cmd == 1600, "force released: command follows the NEW table (1600 us), not the previous one");
        check(seen1500 == 0, "the previous table's value (1500) never appeared after the swap");

        // ===== S3: ADC timeout fault (sensor gone) during an upload + COMMIT
        adc_connected = 0;
        w0 = 0; while (!fault_led[2] && w0 < 400_000) begin @(posedge clk); w0 = w0 + 1; end
        check(fault_led[2] === 1'b1, "MISO disconnected: ADC timeout fault raised");
        ticks(200);
        check(pulse_cmd == 1000, "ADC timeout: SAFE");
        g0 = n_good; s0 = n_swap;
        upload(1, -1, -1, 1);
        wait_frames(g0 + 66, 2_000_000); ticks(500);
        check(last_st === 8'h07 && n_swap == s0 + 1, "COMMIT during an ADC timeout fault: COMMITTED, swap happened");
        check(pulse_cmd == 1000 && fault_led[2] === 1'b1, "...servo command stayed SAFE");
        adc_connected = 1; do_reset;
        check(fault_led == 4'b0000 && pulse_cmd == 1500, "sensor back + reset: table committed during the fault is live (1500 us)");

        // ===== S4: failed uploads leave the live table and the servo command untouched
        settle_samples; s0 = n_swap; c0 = cmd_changes;
        g0 = n_good;
        upload(2, 17, -1, 1);                                                     // 63 entries + COMMIT
        wait_frames(g0 + 65, 2_000_000); ticks(500);
        check(last_st === 8'h15 && last_info === 8'd8, "partial upload (63 entries): COMMIT answered NAK 8 INCOMPLETE");
        g0 = n_good; upload(2, -1, 20, 1);                                        // one out-of-range entry
        ticks(40_000);                                                            // let the error and the quiet period play out
        pkt0(8'h04); ticks(40_000);
        g0 = n_good;
        pkt0(8'h01); uart_byte(8'hA5); uart_byte(8'h02); uart_byte(8'd9);         // BEGIN then a packet cut short
        ticks(60_000);                                                            // > 200 us of silence: upload times out
        pkt0(8'h03); ticks(40_000);
        check(n_swap == s0, "partial, invalid-entry, aborted and timed-out uploads: no lut_swap at all");
        check(cmd_changes == c0 && pulse_cmd == 1500 && fault_led == 4'b0000, "...and the servo command never changed (still 1500 us, no fault)");

        // ===== whole-run invariants
        check(viol_range == 0, "servo command stayed inside 1000..2000 us on every clock of the run");
        check(viol_safe == 0, "servo command was SAFE on every clock where a fault bit had been set for 3 clocks");
        check(u_adc.violations == 0, "MCP3008 timing: zero violations over the run");
        $display("INFO  responses=%0d bad=%0d writes=%0d swaps=%0d commits=%0d", n_good, n_bad, n_wr, n_swap, n_commit);
        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #(WATCHDOG_NS); $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
