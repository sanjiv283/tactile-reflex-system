`timescale 1ns / 1ps
// Stage 3 integration: serial bytes -> uart_rx -> lut_upload_ctrl -> unchanged reflex_top_spi
// (lut_engine, safety_governor, servo PWM) with the MCP3008 model feeding force readings.
// 100 MHz clock. BAUD is raised to 2 Mbaud (50 clocks/bit) so uploads stay fast in simulation;
// uart_rx is also tested at 115200 in tb_uart_rx. Servo frame 2.5 ms (FRAME_US parameter).
// Old table: pulse = 2000 - 16*(adc>>4).  New table: pulse = 1900 - 10*(adc>>4).
module tb_reflex_top_uart;
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

    reflex_top_uart #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .UPLOAD_TIMEOUT_US(200), .SCLK_HZ(1_000_000),
                      .FRAME_US(FRAME_US)) dut (
        .clk(clk), .rst_btn(rst_btn), .estop_btn(estop_btn), .grip_en_sw(grip_en_sw),
        .uart_rxd(uart_rxd),
        .spi_cs_n(cs_n), .spi_sclk(sclk), .spi_mosi(mosi), .spi_miso(adc_dout),
        .servo_out(servo_out), .fault_led(fault_led), .active_bank_led(active_bank_led),
        .dbg_cmd_toggle(dbg_cmd_toggle), .adc_frame_err(adc_ferr),
        .upload_ack(upload_ack), .upload_nak(upload_nak), .upload_err(upload_err),
        .upload_active(upload_active), .upload_failed(upload_failed),
        .upload_entries(upload_entries), .upload_commit(upload_commit));
    mcp3008_model u_adc (.cs_n(cs_n), .sclk(sclk), .din(mosi), .dout(adc_dout));
    pullup (adc_dout);   // the board's MISO pull-up: DOUT is high-impedance until the null bit and adc_spi_interface checks it

    integer errors = 0;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask
    task ticks(input integer n); repeat (n) @(posedge clk); endtask

    wire [11:0] pulse_cmd = dut.u_spi.u_core.pulse_cmd;

    // ---- serial driver (8N1, LSB first)
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
            uart_byte(8'hA5); uart_byte(8'h02); uart_byte({2'b00, a}); uart_byte(h); uart_byte(l);
            uart_byte(8'h02 ^ {2'b00, a} ^ h ^ l);
        end
    endtask
    function [11:0] newv(input integer i); newv = 1900 - 10 * i; endfunction
    task write_new(input integer skip, input integer bad_at);
        integer k, a;
        begin
            for (k = 0; k < 64; k = k + 1) begin
                a = (k * 37) % 64;
                if (a == bad_at)       pkt_write(a[5:0], 12'd5);          // out of range -> NAK
                else if (a != skip)    pkt_write(a[5:0], newv(a));
            end
        end
    endtask

    // ---- observation
    integer n_ack = 0, n_nak = 0, n_commit = 0;
    always @(posedge clk) begin
        if (upload_ack) n_ack = n_ack + 1;
        if (upload_nak) n_nak = n_nak + 1;
        if (upload_commit) n_commit = n_commit + 1;
    end
    realtime t_r, t_f;
    integer w;
    task pulse_w;                          // skip one pulse (may predate a change), measure the next
        begin
            @(posedge servo_out); @(negedge servo_out);
            @(posedge servo_out); t_r = $realtime; @(negedge servo_out); t_f = $realtime;
            w = (t_f - t_r) / 1000.0;
        end
    endtask
    // quick check of the command the governor sends to the servo path (no PWM measurement)
    task expect_cmd(input integer frc, input integer exp_us, input [8*96-1:0] name);
        begin
            u_adc.value[0] = frc; ticks(2 * CONV_CLKS + 50);
            check(pulse_cmd == exp_us && fault_led == 4'b0000, name);
            if (!(pulse_cmd == exp_us)) $display("      force=%0d: pulse_cmd=%0d (exp %0d) fault=%b", frc, pulse_cmd, exp_us, fault_led);
        end
    endtask
    // same, plus the real servo_out pulse width
    task expect_live(input integer frc, input integer exp_us, input [8*96-1:0] name);
        begin
            u_adc.value[0] = frc; ticks(2 * CONV_CLKS + 50); pulse_w;
            check(pulse_cmd == exp_us && w == exp_us && fault_led == 4'b0000, name);
            if (!(pulse_cmd == exp_us && w == exp_us))
                $display("      force=%0d: pulse_cmd=%0d servo=%0d us (exp %0d) fault=%b", frc, pulse_cmd, w, exp_us, fault_led);
        end
    endtask

    integer bank0, c0, k0, a0;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_reflex_top_uart);
        for (c0 = 0; c0 < 8; c0 = c0 + 1) u_adc.value[c0] = 10'd999;
        u_adc.value[0] = 10'd0;
        ticks(40); rst_btn = 0; grip_en_sw = 1; ticks(20);
        bank0 = active_bank_led;

        // ---- baseline: old table drives the servo
        expect_cmd(  0, 2000, "baseline force 0   -> 2000 us (old table)");
        expect_live(640, 1360, "baseline force 640 -> 1360 us (old table)");

        // ---- partial upload (63 of 64) + COMMIT: refused, servo unchanged
        c0 = n_commit; k0 = n_nak;
        pkt0(8'h01); write_new(37, -1); pkt0(8'h03); ticks(200);
        check(n_nak == k0 + 1 && upload_err == 4'd8 && n_commit == c0 && active_bank_led == bank0,
              "63-entry upload: COMMIT refused (INCOMPLETE), no swap");
        expect_cmd(640, 1360, "after partial upload: still 1360 us");

        // ---- all 64 written but never committed
        pkt0(8'h01); write_new(-1, -1); ticks(200);
        check(upload_entries == 64 && upload_active && !upload_failed, "64 entries received, waiting for COMMIT");
        expect_cmd(640, 1360, "64 entries written, no COMMIT: still 1360 us");

        // ---- interrupted: ABORT, then timeout
        pkt0(8'h04); ticks(100);
        check(!upload_active, "ABORT closes the upload");
        pkt0(8'h03); ticks(100);
        check(upload_err == 4'd3 && active_bank_led == bank0, "COMMIT after ABORT refused");
        pkt0(8'h01); write_new(-1, -1);                       // complete table...
        uart_byte(8'hA5); uart_byte(8'h02); uart_byte(8'd3);  // ...but a packet is cut short
        ticks(30_000);                                        // > 200 us of silence
        check(upload_failed && upload_err == 4'd9, "timeout inside a packet fails the upload");
        pkt0(8'h03); ticks(200);
        check(upload_err == 4'd4 && n_commit == c0 && active_bank_led == bank0, "COMMIT after timeout refused (FAILED)");
        expect_cmd(640, 1360, "after ABORT and timeout: still 1360 us");

        // ---- bad entry in the middle poisons the upload
        pkt0(8'h01); write_new(-1, 20); pkt0(8'h03); ticks(200);
        check(upload_failed && n_commit == c0 && active_bank_led == bank0, "upload with an out-of-range entry cannot commit");
        expect_cmd(640, 1360, "after invalid-entry upload: still 1360 us");

        // ---- valid full upload + COMMIT: servo follows the new table
        ticks(30_000);                                        // let the earlier error state settle
        pkt0(8'h01); ticks(100);
        check(upload_active && !upload_failed && upload_entries == 0, "fresh BEGIN after errors");
        write_new(-1, -1); ticks(100);
        check(upload_entries == 64, "all 64 entries received");
        expect_cmd(640, 1360, "before COMMIT the old table is still live");
        pkt0(8'h03); ticks(200);
        check(n_commit == c0 + 1 && active_bank_led != bank0, "COMMIT: one swap, active bank LED toggled");
        expect_live(  0, 1900, "after COMMIT force 0   -> 1900 us (new table)");
        expect_cmd(320, 1700, "after COMMIT force 320 -> 1700 us (new table)");
        expect_live(640, 1500, "after COMMIT force 640 -> 1500 us (new table, servo pulse measured)");

        // ---- governor is still in charge with the new table
        u_adc.value[0] = 950; ticks(2 * CONV_CLKS + 50);
        check(fault_led == 4'b0001 && pulse_cmd == 1000, "over-force 950 still opens the gripper (1000 us)");
        u_adc.value[0] = 640; ticks(2 * CONV_CLKS + 50);
        check(fault_led == 4'b0000 && pulse_cmd == 1500, "released: new table value again");

        // ---- reset keeps the committed table; a stray WRITE after reset does nothing
        @(posedge clk) rst_btn = 1; ticks(5); rst_btn = 0; ticks(2 * CONV_CLKS + 200);
        pkt_write(6'd40, 12'd1111); ticks(100);
        check(upload_err == 4'd3, "WRITE after reset (no BEGIN) refused");
        expect_cmd(640, 1500, "after reset: committed table kept, stray WRITE ignored");

        check(u_adc.violations == 0, "MCP3008 timing: zero violations over the run");
        $display("INFO  uploads: ack=%0d nak=%0d commits=%0d", n_ack, n_nak, n_commit);
        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #(WATCHDOG_NS); $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
