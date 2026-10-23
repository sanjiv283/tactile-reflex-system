`timescale 1ns / 1ps
// Stage 4 integration: a HOST MODEL talks to the unchanged reflex_top_uart over serial lines
// (uart_rxd command packets, uart_txd response frames) with the MCP3008 model feeding the SPI path.
// Every response is compared with what the controller and the LUT actually did (write / swap
// pulses, bank LED, servo command), so a response can only pass if it tells the truth.
// 100 MHz clock; BAUD 2 Mbaud (50 clocks/bit) and a 200 us upload timeout only to keep simulation
// short (uart_tx / uart_rx are also tested at 115200 in their own testbenches).
module tb_reflex_top_host;
    parameter FRAME_US    = 2500;
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

    reflex_top_uart #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .UPLOAD_TIMEOUT_US(200), .SCLK_HZ(1_000_000),
                      .FRAME_US(FRAME_US), .RESP_FIFO_DEPTH(4)) dut (
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

    // ---------------- ground truth from inside the DUT
    integer n_wr = 0, n_swap = 0, n_commit = 0, n_ack = 0, n_nak = 0;
    always @(posedge clk) begin
        if (dut.wr_en) n_wr = n_wr + 1;
        if (dut.swap)  n_swap = n_swap + 1;
        if (upload_commit) n_commit = n_commit + 1;
        if (upload_ack) n_ack = n_ack + 1;
        if (upload_nak) n_nak = n_nak + 1;
    end

    // ---------------- host side: serial transmitter for commands
    task uart_byte(input [7:0] b);
        integer k;
        begin
            uart_rxd = 0; #(BIT_NS);
            for (k = 0; k < 8; k = k + 1) begin uart_rxd = b[k]; #(BIT_NS); end
            uart_rxd = 1; #(BIT_NS);
        end
    endtask
    task pkt0(input [7:0] cmd); begin uart_byte(8'hA5); uart_byte(cmd); uart_byte(cmd); end endtask
    task pkt_write(input [7:0] a, input [7:0] h, input [7:0] l);
        begin uart_byte(8'hA5); uart_byte(8'h02); uart_byte(a); uart_byte(h); uart_byte(l); uart_byte(8'h02 ^ a ^ h ^ l); end
    endtask
    task pkt_write_v(input [5:0] a, input [11:0] v); begin pkt_write({2'b00, a}, {4'h0, v[11:8]}, v[7:0]); end endtask
    task pkt_write_badchk(input [7:0] a, input [7:0] h, input [7:0] l);
        begin uart_byte(8'hA5); uart_byte(8'h02); uart_byte(a); uart_byte(h); uart_byte(l); uart_byte((8'h02 ^ a ^ h ^ l) ^ 8'h01); end
    endtask
    task quiet_gap; begin ticks(30_000); end endtask                 // 300 us > 200 us timeout

    // ---------------- host side: response receiver + parser (documented algorithm)
    wire [7:0] mdata; wire mvalid; wire [31:0] mn, mfe;
    uart_monitor #(.BIT_NS(BIT_NS)) mon (.rx(uart_txd), .data(mdata), .valid(mvalid), .n_bytes(mn), .n_fe(mfe));

    reg [1:0] pst = 0;
    reg [7:0] p_st, p_info;
    integer n_good = 0, n_bad = 0, n_resync = 0;
    reg [7:0] f_st [0:511]; reg [7:0] f_info [0:511]; real f_t [0:511];
    function frame_ok(input [7:0] st, input [7:0] info);
        reg [7:0] b;
        begin
            b = st & 8'h7F;
            frame_ok = (b == 8'h06 && info <= 64) || (b == 8'h07 && info == 64) || (b == 8'h15 && info >= 1 && info <= 10);
        end
    endfunction
    always @(posedge mvalid) begin : parser
        reg [7:0] b;
        b = mdata;
        case (pst)
            2'd0: if (b == 8'h5A) pst = 1;
            2'd1: if (b == 8'h5A) begin n_resync = n_resync + 1; pst = 1; end else begin p_st = b; pst = 2; end
            2'd2: if (b == 8'h5A) begin n_resync = n_resync + 1; pst = 1; end else begin p_info = b; pst = 3; end
            2'd3: if (b == 8'h5A) begin n_resync = n_resync + 1; pst = 1; end
                  else begin
                      if (b == (p_st ^ p_info) && frame_ok(p_st, p_info)) begin
                          f_st[n_good % 512] = p_st; f_info[n_good % 512] = p_info; f_t[n_good % 512] = $realtime;
                          n_good = n_good + 1;
                      end else n_bad = n_bad + 1;
                      pst = 0;
                  end
        endcase
    end

    // ---------------- response consumption: frame k is the k-th good frame since 'ridx' started
    integer ridx = 0;
    reg [7:0] r_st, r_info; reg r_got;
    task get_resp(input integer max_clks);          // waits for the next frame
        integer w;
        begin
            w = 0; r_got = 0;
            while (n_good <= ridx && w < max_clks) begin @(posedge clk); w = w + 1; end
            if (n_good > ridx) begin r_st = f_st[ridx % 512]; r_info = f_info[ridx % 512]; ridx = ridx + 1; r_got = 1; end
        end
    endtask
    integer w0, s0, c0, a0, bank_before;
    task snap; begin w0 = n_wr; s0 = n_swap; c0 = n_commit; bank_before = active_bank_led; end endtask

    // expect an ACK (kind 6) / COMMITTED (7) / NAK (0x15) with the given INFO and lost flag, plus the ground-truth effect
    task expect_ack(input [6:0] entries, input integer exp_wr, input [8*96-1:0] name);
        begin
            get_resp(100_000);
            check(r_got && r_st === 8'h06 && r_info === {1'b0, entries} && n_wr == w0 + exp_wr && n_swap == s0, name);
            if (!(r_got && r_st === 8'h06 && r_info === {1'b0, entries}))
                $display("      got=%b status=%h info=%0d (exp ACK %0d)", r_got, r_st, r_info, entries);
        end
    endtask
    task expect_nak(input [3:0] code, input [8*96-1:0] name);
        begin
            get_resp(100_000);
            check(r_got && r_st === 8'h15 && r_info === {4'h0, code} && n_wr == w0 && n_swap == s0 && upload_err == code, name);
            if (!(r_got && r_st === 8'h15 && r_info === {4'h0, code}))
                $display("      got=%b status=%h info=%0d (exp NAK %0d)", r_got, r_st, r_info, code);
        end
    endtask
    task expect_committed(input [8*96-1:0] name);
        begin
            get_resp(100_000);
            check(r_got && r_st === 8'h07 && r_info === 8'd64 && n_swap == s0 + 1 && n_commit == c0 + 1 &&
                  n_wr == w0 && active_bank_led != bank_before, name);
        end
    endtask
    task expect_no_more(input [8*96-1:0] name);   // nothing else arrives
        integer g;
        begin g = n_good; ticks(3000); check(n_good == g && !tx_busy, name); end
    endtask

    function [11:0] vA(input integer i); vA = 1900 - 10 * i; endfunction      // table A: idx 40 -> 1500
    function [11:0] vB(input integer i); vB = 1800 -  5 * i; endfunction      // table B: idx 40 -> 1600

    integer i, k, a, nresp, nlost, bad0, resync0, dist, fr0, ok_i;
    real tlast, tresp;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_reflex_top_host);
        for (i = 0; i < 8; i = i + 1) u_adc.value[i] = 10'd999;
        u_adc.value[0] = 10'd640;
        ticks(40); rst_btn = 0; grip_en_sw = 1; ticks(2 * CONV_CLKS + 200);
        check(uart_txd === 1'b1 && !tx_busy && !resp_overflow, "reset released: TX line idle high, no responses pending");
        check(pulse_cmd == 1360, "baseline: force 640 -> 1360 us (power-up table)");

        // ===== T1: stop-and-wait upload with a duplicate, then an incomplete COMMIT
        snap; pkt0(8'h01);                 expect_ack(7'd0, 0, "BEGIN -> ACK, entries 0");
        dist = 0;
        for (k = 0; k < 64; k = k + 1) begin
            a = (k * 37) % 64;
            if (a != 37) begin
                snap; pkt_write_v(a[5:0], vA(a)); dist = dist + 1;
                get_resp(100_000);
                if (!(r_got && r_st === 8'h06 && r_info === dist[7:0] && n_wr == w0 + 1 && n_swap == s0)) begin
                    errors = errors + 1; $display("FAIL  WRITE #%0d addr %0d: got=%b st=%h info=%0d (exp ACK %0d, 1 write)", k, a, r_got, r_st, r_info, dist);
                end
                if (k == 10) begin                       // duplicate of an address already written: count unchanged
                    snap; pkt_write_v(a[5:0], vA(a));
                    get_resp(100_000);
                    check(r_got && r_st === 8'h06 && r_info === dist[7:0] && n_wr == w0 + 1, "duplicate WRITE -> ACK, entries count unchanged");
                end
            end
        end
        check(dist == 63 && upload_entries == 63, "63 distinct entries received (address 37 withheld)");
        snap; pkt0(8'h03);                 expect_nak(4'd8, "COMMIT with 63 entries -> NAK 8 INCOMPLETE, no swap");
        snap; pkt_write_v(6'd37, vA(37));  expect_nak(4'd4, "late WRITE -> NAK 4 FAILED, nothing written");
        snap; pkt0(8'h03);                 expect_nak(4'd4, "COMMIT -> NAK 4 FAILED, no swap");
        check(pulse_cmd == 1360 && n_swap == 0, "live table untouched: servo command still 1360 us");

        // ===== T2: complete upload then COMMIT -> COMMITTED, matches the real swap
        snap; pkt0(8'h01);                 expect_ack(7'd0, 0, "fresh BEGIN -> ACK 0 (failure cleared)");
        ok_i = 1;
        for (k = 0; k < 64; k = k + 1) begin
            a = (k * 37) % 64; snap; pkt_write_v(a[5:0], vA(a)); get_resp(100_000);
            if (!(r_got && r_st === 8'h06 && r_info === (k + 1) && n_wr == w0 + 1)) ok_i = 0;
        end
        check(ok_i, "64 WRITEs -> 64 ACKs counting 1..64");
        check(pulse_cmd == 1360, "all 64 written, not committed: servo command still 1360 us");
        snap; pkt0(8'h03);                 expect_committed("COMMIT -> COMMITTED(64): one swap, one commit pulse, bank LED toggled");
        ticks(2 * CONV_CLKS + 100);
        check(pulse_cmd == 1500, "after COMMITTED the servo command follows the new table: 1500 us");
        snap; pkt0(8'h03);                 expect_nak(4'd3, "second COMMIT -> NAK 3 NOT_ACTIVE, no second swap");

        // ===== T3: rejected commands, each NAK checked against the ground truth
        snap; pkt_write_v(6'd5, 12'd1500);  expect_nak(4'd3, "WRITE without BEGIN -> NAK 3 NOT_ACTIVE");
        snap; pkt0(8'h01);                  expect_ack(7'd0, 0, "BEGIN -> ACK");
        snap; pkt_write(8'd64, 8'h05, 8'hDC); expect_nak(4'd5, "WRITE addr 64 -> NAK 5 ADDR");
        snap; pkt0(8'h01);                  expect_ack(7'd0, 0, "BEGIN -> ACK");
        snap; pkt_write(8'd3, 8'h10, 8'hDC);  expect_nak(4'd6, "WRITE with DATA_H upper nibble -> NAK 6 DATA");
        snap; pkt0(8'h01);                  expect_ack(7'd0, 0, "BEGIN -> ACK");
        snap; pkt_write_v(6'd3, 12'd999);   expect_nak(4'd7, "WRITE 999 us -> NAK 7 RANGE");
        snap; pkt0(8'h01);                  expect_ack(7'd0, 0, "BEGIN -> ACK");
        snap; pkt_write_v(6'd3, 12'd2001);  expect_nak(4'd7, "WRITE 2001 us -> NAK 7 RANGE");
        snap; pkt0(8'h01);                  expect_ack(7'd0, 0, "BEGIN -> ACK");
        snap; pkt_write_v(6'd3, 12'd1000);  expect_ack(7'd1, 1, "WRITE 1000 us (boundary) -> ACK, 1 write");
        snap; pkt0(8'h04);                  expect_ack(7'd1, 0, "ABORT -> ACK, nothing swapped");
        snap; pkt0(8'h03);                  expect_nak(4'd3, "COMMIT after ABORT -> NAK 3 NOT_ACTIVE");
        // checksum error and unknown command: NAK, then the quiet period swallows the next bytes
        snap; pkt0(8'h01);                  expect_ack(7'd0, 0, "BEGIN -> ACK");
        snap; pkt_write_badchk(8'd9, 8'h05, 8'hDC); expect_nak(4'd1, "bad checksum -> NAK 1 CHK, nothing written");
        snap; pkt0(8'h01);                  expect_no_more("packet right after a checksum error is swallowed: no response");
        quiet_gap;
        snap; pkt0(8'h01);                  expect_ack(7'd0, 0, "after the quiet period a fresh BEGIN -> ACK");
        snap; uart_byte(8'hA5); uart_byte(8'h7F); expect_nak(4'd2, "unknown CMD 0x7F -> NAK 2 CMD");
        quiet_gap;
        snap; uart_byte(8'h00); uart_byte(8'hFF); uart_byte(8'h13);  expect_no_more("garbage before SOF produces no response");
        // timeout: asynchronous NAK 9 with no command of its own
        snap; pkt0(8'h01);                  expect_ack(7'd0, 0, "BEGIN -> ACK");
        uart_byte(8'hA5); uart_byte(8'h02); uart_byte(8'd5); tlast = $realtime;   // packet cut short
        get_resp(100_000); tresp = f_t[(ridx - 1) % 512];
        check(r_got && r_st === 8'h15 && r_info === 8'd9 && n_wr == w0 && n_swap == s0, "cut-short packet -> asynchronous NAK 9 TIMEOUT");
        check((tresp - tlast) > 190_000 && (tresp - tlast) < 260_000, "the timeout NAK arrives about 200 us after the last byte");
        snap; pkt0(8'h03);                  expect_nak(4'd4, "COMMIT after timeout -> NAK 4 FAILED");
        snap; pkt0(8'h01);                  expect_ack(7'd0, 0, "BEGIN right after a timeout -> ACK (no quiet period after a timeout)");
        check(pulse_cmd == 1500, "through all of that the live table still gives 1500 us");

        // ===== T4: pipelined upload (no waiting between packets), responses in order, no loss
        fr0 = ridx;
        snap; pkt0(8'h04);                  expect_ack(7'd0, 0, "ABORT -> ACK");
        pkt0(8'h01);
        for (k = 0; k < 64; k = k + 1) begin a = (k * 29 + 3) % 64; pkt_write_v(a[5:0], vB(a)); end
        pkt0(8'h03);
        ok_i = 1; nlost = 0;
        for (k = 0; k < 66; k = k + 1) begin
            get_resp(100_000);
            if (!r_got) ok_i = 0;
            else if (k == 0) begin if (!(r_st === 8'h06 && r_info === 8'd0)) ok_i = 0; end
            else if (k <= 64) begin if (!(r_st === 8'h06 && r_info === k[7:0])) ok_i = 0; end
            else begin if (!(r_st === 8'h07 && r_info === 8'd64)) ok_i = 0; end
            if (r_st[7]) nlost = nlost + 1;
        end
        check(ok_i && nlost == 0, "pipelined BEGIN + 64 WRITEs + COMMIT -> 66 responses in order (ACK 0, ACK 1..64, COMMITTED)");
        check(!resp_overflow, "no response was dropped while WRITEs are pipelined (4-byte reply < 6-byte WRITE)");
        check(n_swap == 2 && n_commit == 2, "exactly two swaps so far (two COMMITTED responses)");
        ticks(2 * CONV_CLKS + 100);
        check(pulse_cmd == 1600, "after the second COMMITTED the servo command follows table B: 1600 us");

        // ===== T5: a burst of short commands outruns the reply line -> responses dropped, flagged, still in order
        nresp = 0; nlost = 0; bad0 = n_bad;
        fr0 = ridx;
        for (k = 0; k < 40; k = k + 1) pkt0(8'h01);          // 40 x BEGIN back to back (3 bytes in, 4 bytes out)
        ticks(40_000);
        while (n_good > ridx) begin get_resp(10); nresp = nresp + 1; if (r_st[7]) nlost = nlost + 1;
                                    if (!(r_st[6:0] === 7'h06 && r_info === 8'd0)) begin errors = errors + 1; $display("FAIL  burst response %0d malformed: %h %h", nresp, r_st, r_info); end end
        $display("INFO  burst of 40 BEGIN: %0d responses received, %0d flagged lost, overflow=%b", nresp, nlost, resp_overflow);
        check(nresp >= 5 && nresp < 40, "burst of 40 BEGIN: some answered, some dropped");
        check(nlost >= 1 && resp_overflow, "a response carries the lost flag and the sticky overflow output is set");
        check(n_bad == bad0, "every frame that did arrive is intact");
        snap; pkt0(8'h01); get_resp(100_000);
        snap; pkt0(8'h01);                  expect_ack(7'd0, 0, "later responses are clean again (flag cleared)");

        // ===== T6: reset during transmission
        ticks(30_000);
        snap; pkt0(8'h01);
        resync0 = n_resync;
        @(negedge uart_txd);                                 // response frame has started
        ticks(1100);                                         // 2.2 bytes in: inside the INFO byte (SOF and STATUS already sent)
        @(posedge clk); rst_btn = 1;
        ticks(6);
        check(uart_txd === 1'b1 && !tx_busy, "reset mid-response: TX line idle high, transmitter stopped");
        ticks(2); rst_btn = 0;
        k = mn; ticks(5000);
        check(uart_txd === 1'b1 && !tx_busy && mn <= k + 1, "after reset the line stays idle (no leftover response)");
        check(!resp_overflow, "reset cleared the overflow flag");
        ridx = n_good;                                       // the cut-off frame is dropped by the host
        snap; pkt_write_v(6'd8, 12'd1500);  expect_nak(4'd3, "after reset: upload state gone, WRITE -> NAK 3 NOT_ACTIVE");
        snap; pkt0(8'h01);                  expect_ack(7'd0, 0, "after reset: BEGIN -> ACK, parser recovered on the next 0x5A");
        check(r_st === 8'h06, "recovered response is clean (no stale lost flag)");
        check(n_resync > resync0 && n_bad == bad0, "the cut-off frame made the parser resynchronise on the next 0x5A, and no response was invented");

        // ===== end of run bookkeeping
        check(n_commit == n_swap, "every swap had a commit_done, every COMMITTED a swap");
        check(u_adc.violations == 0, "MCP3008 timing: zero violations over the run");
        $display("INFO  responses parsed=%0d bad=%0d resync=%0d, ack=%0d nak=%0d writes=%0d swaps=%0d", n_good, n_bad, n_resync, n_ack, n_nak, n_wr, n_swap);
        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #(WATCHDOG_NS); $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
