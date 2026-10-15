`timescale 1ns / 1ps
// Self-checking testbench: lut_upload_ctrl driving the REAL (unchanged) lut_engine.
// Bytes are injected straight onto the rx_data/rx_valid interface (uart_rx is tested separately).
// The live table is read back through lut_engine's normal lookup port, so "unchanged" means the
// values the servo path would actually see.
// Clock 1 MHz, timeout 100 us = 100 clocks (fast simulation; the logic is clock-count based).
module tb_lut_upload_ctrl;
    localparam CLK_HZ = 1_000_000, TIMEOUT_US = 100, TLIM = 100;

    reg clk = 0;
    always #500 clk = ~clk;

    reg        rst = 1;
    reg  [7:0] rx_data = 0;
    reg        rx_valid = 0, rx_frame_err = 0;
    wire       wr_en, swap, ack, nak, commit_done, upl_active, upl_failed, active_bank;
    wire [5:0] wr_addr;
    wire [11:0] wr_data;
    wire [3:0] err_code;
    wire [6:0] entries;
    reg  [9:0] adc_value = 0;
    reg        adc_valid = 0;
    wire [11:0] lut_pulse;
    wire        lut_valid;

    lut_upload_ctrl #(.CLK_HZ(CLK_HZ), .TIMEOUT_US(TIMEOUT_US)) dut (
        .clk(clk), .rst(rst), .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_frame_err),
        .lut_wr_en(wr_en), .lut_wr_addr(wr_addr), .lut_wr_data(wr_data), .lut_swap(swap),
        .ack(ack), .nak(nak), .err_code(err_code), .commit_done(commit_done),
        .upload_active(upl_active), .upload_failed(upl_failed), .entries(entries));

    lut_engine u_lut (
        .clk(clk), .rst(rst), .adc_value(adc_value), .adc_valid(adc_valid),
        .lut_pulse_us(lut_pulse), .lut_valid(lut_valid),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .swap(swap), .active_bank(active_bank));

    integer errors = 0;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask

    // ---- monitors
    integer n_ack = 0, n_nak = 0, n_wr = 0, n_swap = 0, n_commit = 0, wide_swap = 0;
    reg [3:0] last_err = 0;
    reg ps = 0;
    always @(posedge clk) begin
        if (ack) n_ack = n_ack + 1;
        if (nak) begin n_nak = n_nak + 1; last_err = err_code; end
        if (wr_en) n_wr = n_wr + 1;
        if (swap) n_swap = n_swap + 1;
        if (commit_done) n_commit = n_commit + 1;
        if (swap && ps) wide_swap = wide_swap + 1;
        if (swap && wr_en) begin $display("FAIL  write and swap in the same clock"); errors = errors + 1; end
        ps <= swap;
    end
    integer a0, k0, w0, s0;
    task snap; begin a0 = n_ack; k0 = n_nak; w0 = n_wr; s0 = n_swap; end endtask
    task exp_ack(input integer nwr, input [8*96-1:0] name);
        begin
            check(n_ack == a0 + 1 && n_nak == k0 && n_wr == w0 + nwr, name);
        end
    endtask
    task exp_nak(input [3:0] code, input [8*96-1:0] name);
        begin
            check(n_nak == k0 + 1 && n_ack == a0 && n_wr == w0 && n_swap == s0 && last_err == code, name);
        end
    endtask

    // ---- byte / packet drivers (a byte every 4 clocks)
    task send_byte(input [7:0] b);
        begin @(negedge clk); rx_data = b; rx_valid = 1; @(negedge clk); rx_valid = 0; repeat (2) @(negedge clk); end
    endtask
    task settle; begin repeat (6) @(negedge clk); end endtask
    task quiet_gap; begin repeat (TLIM + 30) @(negedge clk); end endtask
    task pkt0(input [7:0] cmd); begin send_byte(8'hA5); send_byte(cmd); send_byte(cmd); settle; end endtask
    task pkt_write(input [7:0] a, input [7:0] h, input [7:0] l);
        begin send_byte(8'hA5); send_byte(8'h02); send_byte(a); send_byte(h); send_byte(l);
              send_byte(8'h02 ^ a ^ h ^ l); settle; end
    endtask
    task pkt_write_badchk(input [7:0] a, input [7:0] h, input [7:0] l);
        begin send_byte(8'hA5); send_byte(8'h02); send_byte(a); send_byte(h); send_byte(l);
              send_byte((8'h02 ^ a ^ h ^ l) ^ 8'h10); settle; end
    endtask
    task w_val(input [5:0] a, input [11:0] v); begin pkt_write({2'b00, a}, {4'h0, v[11:8]}, v[7:0]); end endtask

    // ---- tables
    reg [11:0] oldtab [0:63];
    reg [11:0] newtab [0:63];
    reg [11:0] tabB   [0:63];
    reg [11:0] got    [0:63];
    integer i, j;
    initial for (i = 0; i < 64; i = i + 1) begin
        oldtab[i] = 2000 - 16 * i;          // lut_engine power-up table
        newtab[i] = 1000 + 10 * i;          // 1000..1630
        tabB[i]   = 1900 - 7 * i;           // 1900..1459
    end

    // read the live table back through the normal lookup path
    task read_table;
        integer k;
        begin
            for (k = 0; k < 64; k = k + 1) begin
                @(negedge clk); adc_value = {k[5:0], 4'b0000}; adc_valid = 1;
                @(negedge clk); adc_valid = 0; got[k] = lut_pulse;
            end
        end
    endtask
    function integer mismatches_vs(input integer which);   // 0 old, 1 new, 2 tabB
        integer k, m;
        begin
            m = 0;
            for (k = 0; k < 64; k = k + 1)
                if (got[k] !== (which == 0 ? oldtab[k] : which == 1 ? newtab[k] : tabB[k])) m = m + 1;
            mismatches_vs = m;
        end
    endfunction
    task live_is(input integer which, input [8*96-1:0] name);
        begin read_table; check(mismatches_vs(which) == 0, name); end
    endtask

    // write all 64 entries of 'which' table in a scrambled order (37 is coprime with 64)
    task write_all(input integer which, input integer skip);
        integer k, a;
        begin
            for (k = 0; k < 64; k = k + 1) begin
                a = (k * 37) % 64;
                if (a != skip) w_val(a[5:0], which == 1 ? newtab[a] : tabB[a]);
            end
        end
    endtask

    integer bank0, sw;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_lut_upload_ctrl);
        repeat (6) @(negedge clk); rst = 0; repeat (4) @(negedge clk);

        // ---------------- reset / baseline
        check(!upl_active && !upl_failed && entries == 0 && !wr_en && !swap, "reset: idle, nothing pending");
        live_is(0, "baseline: live table is the power-up table");
        bank0 = active_bank;

        // ---------------- 1. valid full upload (scrambled order) -> exactly one swap
        snap; pkt0(8'h01); exp_ack(0, "BEGIN accepted");
        check(upl_active && !upl_failed && entries == 0, "BEGIN: active, 0 entries");
        snap; write_all(1, -1);
        check(n_ack == a0 + 64 && n_wr == w0 + 64 && n_nak == k0 && entries == 64, "64 WRITEs accepted, 64 distinct entries");
        live_is(0, "all 64 written, NOT committed: live table still unchanged");
        check(active_bank == bank0 && n_swap == s0, "no swap before COMMIT");
        snap; pkt0(8'h03); exp_ack(0, "COMMIT accepted");
        check(n_swap == s0 + 1 && n_commit == 1 && active_bank != bank0 && !upl_active, "exactly one swap, bank toggled, upload closed");
        live_is(1, "after COMMIT the live table is the new table");
        check(wide_swap == 0, "lut_swap is a single-clock pulse");
        snap; w_val(6'd5, 12'd1500); exp_nak(4'd3, "WRITE after COMMIT refused (NOT_ACTIVE), live bank safe");
        snap; pkt0(8'h03); exp_nak(4'd3, "second COMMIT refused (NOT_ACTIVE), no second swap");
        live_is(1, "table still the new table");

        // ---------------- 2. partial upload (63 of 64) -> COMMIT refused, never swapped
        sw = n_swap;
        pkt0(8'h01); write_all(2, 17);
        check(entries == 63, "63 distinct entries");
        snap; pkt0(8'h03); exp_nak(4'd8, "COMMIT with 63 entries refused (INCOMPLETE)");
        check(upl_failed, "incomplete COMMIT marks the upload failed");
        snap; w_val(6'd17, tabB[17]); exp_nak(4'd4, "late WRITE refused after failure (FAILED)");
        snap; pkt0(8'h03); exp_nak(4'd4, "COMMIT refused again (FAILED)");
        check(n_swap == sw, "no swap after partial upload");
        live_is(1, "live table unchanged after partial upload");
        // recovery with a fresh BEGIN
        pkt0(8'h01); check(upl_active && !upl_failed && entries == 0, "fresh BEGIN clears failure and entries");
        write_all(2, -1); snap; pkt0(8'h03); exp_ack(0, "complete upload after recovery accepted");
        check(n_swap == sw + 1, "recovery upload swapped once");
        live_is(2, "live table is now table B (all 64 entries from the second upload)");

        // ---------------- 3. duplicates: count distinct addresses, not WRITE commands
        sw = n_swap;
        pkt0(8'h01); for (i = 0; i < 64; i = i + 1) w_val(6'd0, newtab[0]);
        check(n_wr >= 64 && entries == 1, "64 WRITEs to one address count as 1");
        snap; pkt0(8'h03); exp_nak(4'd8, "COMMIT after 64 duplicate WRITEs refused");
        pkt0(8'h01); for (i = 0; i < 63; i = i + 1) w_val(i[5:0], newtab[i]);
        w_val(6'd62, newtab[62]);
        check(entries == 63, "63 distinct + 1 duplicate = 64 WRITEs, 63 distinct");
        snap; pkt0(8'h03); exp_nak(4'd8, "COMMIT with 64 WRITEs but 63 distinct refused");
        check(n_swap == sw, "no swap on duplicate-padded upload");
        live_is(2, "live table unchanged after duplicate-padded attempts");
        pkt0(8'h01); for (i = 0; i < 63; i = i + 1) w_val(i[5:0], newtab[i]);
        w_val(6'd5, newtab[5]); w_val(6'd5, newtab[5]); w_val(6'd63, newtab[63]);
        check(entries == 64, "65 WRITEs with 1 duplicate = 64 distinct");
        snap; pkt0(8'h03); exp_ack(0, "COMMIT with all 64 distinct (plus duplicates) accepted");
        live_is(1, "live table is the new table (duplicate writes of identical data)");

        // ---------------- 4. invalid address / data: each rejects and fails the upload
        sw = n_swap;
        pkt0(8'h01);
        snap; pkt_write(8'd64, 8'h05, 8'hDC);  exp_nak(4'd5, "ADDR 64 refused");
        check(upl_failed, "upload failed after bad address");
        pkt0(8'h01);
        snap; pkt_write(8'd255, 8'h05, 8'hDC); exp_nak(4'd5, "ADDR 255 refused");
        pkt0(8'h01);
        snap; pkt_write(8'd3, 8'h10, 8'hDC);   exp_nak(4'd6, "DATA_H upper nibble set refused");
        pkt0(8'h01);
        snap; w_val(6'd3, 12'd999);            exp_nak(4'd7, "999 us (below PULSE_MIN) refused");
        pkt0(8'h01);
        snap; w_val(6'd3, 12'd2001);           exp_nak(4'd7, "2001 us (above PULSE_MAX) refused");
        pkt0(8'h01);
        snap; w_val(6'd3, 12'd0);              exp_nak(4'd7, "0 us refused");
        pkt0(8'h01);
        snap; w_val(6'd3, 12'd4095);           exp_nak(4'd7, "4095 us refused");
        pkt0(8'h01);
        snap; w_val(6'd0, 12'd1000);           exp_ack(1, "boundary 1000 us accepted");
        snap; w_val(6'd1, 12'd2000);           exp_ack(1, "boundary 2000 us accepted");
        // a bad entry anywhere poisons the upload: the remaining valid entries + COMMIT cannot swap
        pkt0(8'h01); for (i = 0; i < 10; i = i + 1) w_val(i[5:0], newtab[i]);
        w_val(6'd10, 12'd5);
        for (i = 11; i < 64; i = i + 1) w_val(i[5:0], newtab[i]);
        snap; pkt0(8'h03); exp_nak(4'd4, "COMMIT after a rejected WRITE refused (FAILED)");
        check(n_swap == sw, "no swap after invalid-data upload");
        live_is(1, "live table unchanged after invalid-data uploads");

        // ---------------- 5. WRITE / COMMIT without BEGIN
        pkt0(8'h04);                                   // make sure nothing is active
        snap; w_val(6'd0, 12'd1500); exp_nak(4'd3, "WRITE without BEGIN refused");
        snap; pkt0(8'h03);           exp_nak(4'd3, "COMMIT without BEGIN refused");
        check(!upl_failed, "refusals outside an upload do not create a failed upload");

        // ---------------- 6. ABORT
        sw = n_swap;
        pkt0(8'h01); for (i = 0; i < 20; i = i + 1) w_val(i[5:0], tabB[i]);
        snap; pkt0(8'h04); exp_ack(0, "ABORT accepted");
        check(!upl_active && !upl_failed, "ABORT: upload closed");
        snap; pkt0(8'h03); exp_nak(4'd3, "COMMIT after ABORT refused");
        check(n_swap == sw, "no swap after ABORT");
        live_is(1, "live table unchanged after ABORT");

        // ---------------- 7. checksum error -> QUIET until the line is idle
        pkt0(8'h01); for (i = 0; i < 5; i = i + 1) w_val(i[5:0], newtab[i]);
        snap; pkt_write_badchk(8'd9, 8'h05, 8'hDC); exp_nak(4'd1, "bad checksum refused (CHK), nothing written");
        check(upl_failed, "bad checksum fails the upload");
        snap; pkt0(8'h01);
        check(n_ack == a0 && n_nak == k0 && !(upl_active && !upl_failed),
              "packet sent right after the error is swallowed (QUIET), by design");
        quiet_gap;
        snap; pkt0(8'h01); exp_ack(0, "after >= TIMEOUT of silence, a fresh BEGIN is accepted");
        check(upl_active && !upl_failed && entries == 0, "recovered by fresh BEGIN");

        // ---------------- 8. unknown command -> QUIET
        snap; send_byte(8'hA5); send_byte(8'h7F); settle;
        exp_nak(4'd2, "unknown CMD 0x7F refused (CMD)");
        check(upl_failed, "unknown CMD fails the upload");
        send_byte(8'hA5); send_byte(8'h01); send_byte(8'h01); settle;      // swallowed
        check(upl_failed, "bytes right after an unknown CMD are ignored (QUIET)");
        quiet_gap; pkt0(8'h01); check(upl_active && !upl_failed, "recovery by fresh BEGIN after the gap");

        // ---------------- 9. leading garbage / resync, 0xA5 inside payloads
        send_byte(8'h00); send_byte(8'hFF); send_byte(8'h01); send_byte(8'h5A);
        snap; pkt0(8'h01); exp_ack(0, "garbage before SOF skipped, BEGIN accepted");
        snap; w_val(6'd7, 12'h5A5); exp_ack(1, "DATA_L = 0xA5 inside a payload is data, not SOF");
        snap; pkt_write(8'd8, 8'h05, 8'hA5); exp_ack(1, "same for a second 0xA5 payload (1445 us)");
        // a corrupted packet containing 0xA5, immediately followed by a good packet: swallowed
        snap; pkt_write_badchk(8'd9, 8'h05, 8'hA5);
        exp_nak(4'd1, "corrupted packet with 0xA5 payload refused");
        snap; pkt_write(8'd10, 8'h05, 8'hDC);
        check(n_ack == a0 && n_nak == k0 && n_wr == w0, "good packet right behind a corrupted one is not executed (QUIET)");
        quiet_gap; pkt0(8'h04);

        // ---------------- 10. timeout inside a packet; idle gap between packets is fine
        pkt0(8'h01); for (i = 0; i < 5; i = i + 1) w_val(i[5:0], newtab[i]);
        send_byte(8'hA5); send_byte(8'h02); send_byte(8'd5);        // packet cut short
        snap; quiet_gap;
        exp_nak(4'd9, "partial packet times out (TIMEOUT)");
        check(upl_failed, "timeout fails the upload");
        snap; pkt0(8'h03); exp_nak(4'd4, "COMMIT after timeout refused (FAILED)");
        snap; pkt0(8'h01); exp_ack(0, "fresh BEGIN right after a timeout accepted (no QUIET after timeout)");
        for (i = 0; i < 32; i = i + 1) w_val(i[5:0], newtab[i]);
        repeat (5 * TLIM) @(negedge clk);                           // long idle between packets
        check(upl_active && !upl_failed && entries == 32, "idle gap between packets does not cancel the upload");
        for (i = 32; i < 64; i = i + 1) w_val(i[5:0], newtab[i]);
        sw = n_swap; snap; pkt0(8'h03); exp_ack(0, "upload resumed after a long idle gap commits");
        check(n_swap == sw + 1, "that commit swapped once");
        live_is(1, "live table is the new table");

        // ---------------- 11. UART framing error mid-packet and between packets
        sw = n_swap;
        pkt0(8'h01); for (i = 0; i < 10; i = i + 1) w_val(i[5:0], tabB[i]);
        send_byte(8'hA5); send_byte(8'h02); send_byte(8'd10);
        snap; @(negedge clk); rx_frame_err = 1; @(negedge clk); rx_frame_err = 0; settle;
        exp_nak(4'd10, "framing error inside a packet refused (UART)");
        check(upl_failed, "framing error fails the upload");
        for (i = 10; i < 64; i = i + 1) w_val(i[5:0], tabB[i]);
        snap; pkt0(8'h03);
        check(n_ack == a0 && n_swap == sw, "rest of the upload and COMMIT are swallowed after the error (QUIET)");
        quiet_gap;
        pkt0(8'h01); for (i = 0; i < 64; i = i + 1) w_val(i[5:0], tabB[i]);
        check(entries == 64 && !upl_failed, "fresh BEGIN after the error: complete upload");
        pkt0(8'h01); for (i = 0; i < 4; i = i + 1) w_val(i[5:0], tabB[i]);
        @(negedge clk); rx_frame_err = 1; @(negedge clk); rx_frame_err = 0; settle;
        check(upl_failed, "framing error between packets also fails an active upload");
        snap; quiet_gap; pkt0(8'h03); exp_nak(4'd4, "COMMIT refused after framing error between packets");
        check(n_swap == sw, "no swap in any framing-error scenario");
        live_is(1, "live table unchanged after framing-error uploads");

        // ---------------- 12. reset in the middle of an upload / of a packet
        pkt0(8'h01); for (i = 0; i < 40; i = i + 1) w_val(i[5:0], tabB[i]);
        @(negedge clk); rst = 1; repeat (3) @(negedge clk); rst = 0; repeat (3) @(negedge clk);
        check(!upl_active && !upl_failed && entries == 0, "reset mid-upload clears the upload state");
        snap; pkt0(8'h03); exp_nak(4'd3, "COMMIT after reset refused (NOT_ACTIVE): partial upload cannot be committed");
        for (i = 40; i < 64; i = i + 1) w_val(i[5:0], tabB[i]);
        snap; pkt0(8'h03); exp_nak(4'd3, "rest of the table + COMMIT without a new BEGIN refused");
        live_is(1, "live table unchanged after reset mid-upload");
        pkt0(8'h01); send_byte(8'hA5); send_byte(8'h02); send_byte(8'd1);
        @(negedge clk); rst = 1; repeat (3) @(negedge clk); rst = 0; repeat (3) @(negedge clk);
        snap; pkt0(8'h01); exp_ack(0, "reset mid-packet: parser back at SOF, next BEGIN accepted");

        // ---------------- global safety properties
        check(n_swap == n_commit, "every lut_swap pulse came with a commit_done (no stray swaps)");
        check(wide_swap == 0, "lut_swap never wider than one clock");
        $display("INFO  totals: ack=%0d nak=%0d writes=%0d swaps=%0d", n_ack, n_nak, n_wr, n_swap);
        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #50_000_000; $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
