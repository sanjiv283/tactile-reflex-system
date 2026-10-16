`timescale 1ns / 1ps
// A complete generated LUT file loaded through the real top level reflex_top_uart (LUT_INIT_FILE -> reflex_top_spi ->
// reflex_top -> lut_engine INIT_FILE). run_sim.sh writes both files in a temporary directory:
//   FILE   hex file written by python/lut_gen.py          (what the RTL loads)
//   EXPECT decimal file written from lut_gen.make_lut()  (independent expected values)
// Checks (nothing is sent over the UART; the UART path is simply idle and must stay harmless):
//   1. hierarchical read of lut_engine's bank0 and bank1 (simulation-only observation, no RTL debug port): all 64 entries of
//      each bank equal the Python value, with 4-state comparisons (an x entry is a mismatch). Exactly 64 comparisons per bank.
//   2. the same again at the end, after normal operation, to show nothing disturbed the tables.
//   3. the real data path: the MCP3008 model supplies ADC codes 16*i+3 for entries 0..56 (codes of entries 57..63 are at or
//      above FORCE_MAX 900, where the governor deliberately goes SAFE), and the governor output (pulse_cmd) must equal the
//      Python value clamped to 1000..2000. Exactly 57 comparisons. This exercises the active bank (bank 0) only.
// Not covered: the second bank through the functional path (needs an upload + COMMIT; covered by other tests), and any
// real FPGA initialisation behaviour.
module tb_lut_uart_top_load;
    parameter FILE   = "";
    parameter EXPECT = "";
    localparam CLK_HZ = 100_000_000, BAUD = 2_000_000, CONV_CLKS = 1751;

    reg clk = 0;
    always #5 clk = ~clk;                             // 100 MHz

    reg  rst_btn = 1, estop_btn = 0, grip_en_sw = 1, uart_rxd = 1;
    wire cs_n, sclk, mosi, adc_dout, servo_out, active_bank_led, dbg_cmd_toggle, adc_ferr, uart_txd, tx_busy, resp_overflow;
    wire [3:0] fault_led, upload_err;
    wire upload_ack, upload_nak, upload_active, upload_failed, upload_commit;
    wire [6:0] upload_entries;

    reflex_top_uart #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .UPLOAD_TIMEOUT_US(200), .SCLK_HZ(1_000_000),
                      .FRAME_US(2500), .LUT_INIT_FILE(FILE)) dut (
        .clk(clk), .rst_btn(rst_btn), .estop_btn(estop_btn), .grip_en_sw(grip_en_sw),
        .uart_rxd(uart_rxd),
        .spi_cs_n(cs_n), .spi_sclk(sclk), .spi_mosi(mosi), .spi_miso(adc_dout),
        .servo_out(servo_out), .fault_led(fault_led), .active_bank_led(active_bank_led),
        .dbg_cmd_toggle(dbg_cmd_toggle), .adc_frame_err(adc_ferr),
        .upload_ack(upload_ack), .upload_nak(upload_nak), .upload_err(upload_err),
        .upload_active(upload_active), .upload_failed(upload_failed),
        .upload_entries(upload_entries), .upload_commit(upload_commit),
        .uart_txd(uart_txd), .tx_busy(tx_busy), .resp_overflow(resp_overflow));
    mcp3008_model u_adc (.cs_n(cs_n), .sclk(sclk), .din(mosi), .dout(adc_dout));

    wire [11:0] pulse_cmd = dut.u_spi.u_core.pulse_cmd;

    integer errors = 0;
    task check(input cond, input [8*112-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask
    task ticks(input integer n); repeat (n) @(posedge clk); endtask

    integer expv [0:63];
    integer fd, n, r, i, nb0, nb1, bad0, bad1, nf, badf, nonidle;
    reg [11:0] w0, w1;

    function integer clamp(input integer v);
        begin clamp = (v < 1000) ? 1000 : (v > 2000) ? 2000 : v; end
    endfunction

    // compare both banks of the real lut_engine with the Python values; counts every comparison made
    task compare_banks;
        begin
            nb0 = 0; nb1 = 0; bad0 = 0; bad1 = 0;
            for (i = 0; i < 64; i = i + 1) begin
                w0 = dut.u_spi.u_core.u_lut.bank0[i];
                w1 = dut.u_spi.u_core.u_lut.bank1[i];
                nb0 = nb0 + 1; nb1 = nb1 + 1;
                if (w0 !== expv[i][11:0]) begin bad0 = bad0 + 1; if (bad0 < 4) $display("      bank0[%0d] = %h, expected %0d", i, w0, expv[i]); end
                if (w1 !== expv[i][11:0]) begin bad1 = bad1 + 1; if (bad1 < 4) $display("      bank1[%0d] = %h, expected %0d", i, w1, expv[i]); end
            end
        end
    endtask

    initial begin #500_000_000; $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end

    initial begin
        check(FILE != "", "an init file path was given (the built-in table is not what is under test)");
        fd = $fopen(EXPECT, "r");
        check(fd != 0, "expected-value file opened");
        n = 0;
        if (fd != 0) begin
            r = 1;
            while (r == 1 && n < 64) begin
                r = $fscanf(fd, "%d\n", expv[n]);
                if (r == 1) n = n + 1;
            end
            $fclose(fd);
        end
        check(n == 64, "expected-value file holds exactly 64 entries");

        ticks(20); rst_btn = 0; ticks(20);

        // ---- 1. the tables, straight after reset
        compare_banks;
        check(nb0 == 64 && bad0 == 0, "reflex_top_uart: bank 0 holds all 64 generated entries (64 comparisons, 0 mismatches or x)");
        check(nb1 == 64 && bad1 == 0, "reflex_top_uart: bank 1 holds all 64 generated entries (64 comparisons, 0 mismatches or x)");
        check(active_bank_led === 1'b0, "bank 0 is the active bank");

        // ---- 3. the real data path: ADC model -> SPI -> lut_engine -> governor
        nf = 0; badf = 0;
        for (i = 0; i < 57; i = i + 1) begin
            u_adc.value[0] = 16 * i + 3;
            ticks(3 * CONV_CLKS + 300);
            nf = nf + 1;
            if (pulse_cmd !== clamp(expv[i])) begin badf = badf + 1; if (badf < 4) $display("      entry %0d: governor output %0d, expected %0d", i, pulse_cmd, clamp(expv[i])); end
        end
        check(nf == 57 && badf == 0, "data path: governor output = Python value (clamped) for entries 0..56 (57 comparisons)");
        check(fault_led === 4'b0000 && adc_ferr === 1'b0, "no fault and no ADC frame error during the sweep");

        // ---- 2. tables unchanged after operation; the idle UART did nothing
        compare_banks;
        check(nb0 == 64 && bad0 == 0 && nb1 == 64 && bad1 == 0, "after operation: both banks still equal the Python values (64 + 64 comparisons)");
        check(uart_txd === 1'b1 && !tx_busy && !resp_overflow && !upload_active && !upload_ack && !upload_nak, "idle UART: no response, no upload activity");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
endmodule
