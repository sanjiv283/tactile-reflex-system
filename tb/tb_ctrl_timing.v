`timescale 1ns / 1ps
// Exact timing boundaries of lut_upload_ctrl (rtl/lut_upload_ctrl.v), driven cycle by cycle.
// Behaviour under test, read from the RTL (TLIM = TIMEOUT_US * (CLK_HZ/1e6) clocks):
//   * `idle` restarts at every rx byte / frame error. Inside a packet, with no byte in the current clock and
//     idle >= TLIM, the packet times out. A byte in the same clock wins (rx_valid is tested first), so the longest
//     distance between two byte-valid clocks that does NOT time out is TLIM+1; TLIM+2 times out.
//   * QUIET (after CHK / CMD / UART errors) leaves only when idle >= TLIM with no byte; a byte at distance TLIM+1
//     from the last byte is still swallowed, a byte at distance TLIM+2 is processed.
//   * Between packets (state SOF) there is no timeout at all.
// Parameter-generic: run with different CLK_HZ / TIMEOUT_US (see run_sim.sh); only the product matters.
module tb_ctrl_timing;
    parameter CLK_HZ_P     = 1_000_000;
    parameter TIMEOUT_US_P = 100;
    localparam L = TIMEOUT_US_P * (CLK_HZ_P / 1_000_000);

    reg clk = 0;
    always #500 clk = ~clk;                        // the controller only counts clocks

    reg        rst = 1, rx_valid = 0, rx_frame_err = 0;
    reg  [7:0] rx_data = 0;
    wire       wr_en, swap, ack, nak, commit_done, active, failed;
    wire [5:0] wr_addr;
    wire [11:0] wr_data;
    wire [3:0] err;
    wire [6:0] entries;
    lut_upload_ctrl #(.CLK_HZ(CLK_HZ_P), .TIMEOUT_US(TIMEOUT_US_P)) dut (
        .clk(clk), .rst(rst), .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_frame_err),
        .lut_wr_en(wr_en), .lut_wr_addr(wr_addr), .lut_wr_data(wr_data), .lut_swap(swap),
        .ack(ack), .nak(nak), .err_code(err), .commit_done(commit_done),
        .upload_active(active), .upload_failed(failed), .entries(entries));

    // declared before task check, which prints them (Icarus 13 reported 'Unable to bind' when these followed the task)
    integer n_ack = 0, n_nak = 0, n_wr = 0, n_swap = 0;
    reg [3:0] last_err = 0;
    integer errors = 0;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s  (acks=%0d naks=%0d last_err=%0d active=%b failed=%b)", name, n_ack, n_nak, last_err, active, failed); errors = errors + 1; end
        end
    endtask
    always @(posedge clk) begin
        if (ack) n_ack = n_ack + 1;
        if (nak) begin n_nak = n_nak + 1; last_err = err; end
        if (wr_en) n_wr = n_wr + 1;
        if (swap) n_swap = n_swap + 1;
    end
    integer a0, k0;
    task snap; begin a0 = n_ack; k0 = n_nak; end endtask

    task nclk(input integer n); repeat (n) @(negedge clk); endtask
    // byte whose valid clock is D clocks after the previous byte's valid clock (D >= 2)
    task send(input [7:0] x, input integer D);
        begin nclk(D - 2); @(negedge clk); rx_data = x; rx_valid = 1; @(negedge clk); rx_valid = 0; end
    endtask
    task first(input [7:0] x); begin @(negedge clk); rx_data = x; rx_valid = 1; @(negedge clk); rx_valid = 0; end endtask
    task settle; begin nclk(6); end endtask
    task ferr; begin @(negedge clk); rx_frame_err = 1; @(negedge clk); rx_frame_err = 0; end endtask
    // complete BEGIN packet with normal 4-clock byte spacing
    task begin_pkt; begin first(8'hA5); send(8'h01, 4); send(8'h01, 4); settle; end endtask
    // let any pending QUIET / timeout expire
    task long_silence; begin nclk(3 * L + 20); end endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_ctrl_timing);
        $display("INFO  controller timeout limit TLIM = %0d clocks (CLK_HZ=%0d, TIMEOUT_US=%0d)", L, CLK_HZ_P, TIMEOUT_US_P);
        nclk(4); rst = 0; nclk(4);

        // ---- gap before the CHK byte of a BEGIN packet
        snap; first(8'hA5); send(8'h01, 4); send(8'h01, L + 1); settle;
        check(n_ack == a0 + 1 && n_nak == k0, "CHK arrives TLIM+1 clocks after CMD: packet accepted (ACK)");
        snap; first(8'hA5); send(8'h01, 4); send(8'h01, L + 2); settle;
        check(n_nak == k0 + 1 && last_err == 4'd9 && n_ack == a0, "CHK arrives TLIM+2 clocks after CMD: TIMEOUT (NAK 9), late byte not used");
        snap; begin_pkt;
        check(n_ack == a0 + 1 && n_nak == k0, "after a timeout the parser is at SOF: next packet accepted at once (no quiet period)");

        // ---- gap before the CMD byte
        snap; first(8'hA5); send(8'h01, L + 1); send(8'h01, 4); settle;
        check(n_ack == a0 + 1 && n_nak == k0, "CMD arrives TLIM+1 clocks after SOF: accepted");
        snap; first(8'hA5); send(8'h01, L + 2); settle;
        check(n_nak == k0 + 1 && last_err == 4'd9, "CMD arrives TLIM+2 clocks after SOF: TIMEOUT (NAK 9)");

        // ---- gap inside a WRITE payload, with an active upload: failure is recorded
        begin_pkt;
        snap; first(8'hA5); send(8'h02, 4); send(8'd5, 4); send(8'h05, L + 1); send(8'hDC, 4); send(8'h02 ^ 8'd5 ^ 8'h05 ^ 8'hDC, 4); settle;
        check(n_ack == a0 + 1 && n_nak == k0 && n_wr == 1 && !failed, "WRITE with a TLIM+1 gap inside the payload: accepted, written once");
        snap; first(8'hA5); send(8'h02, 4); send(8'd6, 4); send(8'h05, L + 2); settle;
        check(n_nak == k0 + 1 && last_err == 4'd9 && failed && n_wr == 1, "WRITE with a TLIM+2 gap inside the payload: TIMEOUT, upload failed, nothing written");
        snap; first(8'hA5); send(8'h03, 4); send(8'h03, 4); settle;
        check(n_nak == k0 + 1 && last_err == 4'd4 && n_swap == 0, "COMMIT after that failure is refused (FAILED): no swap");

        // ---- no timeout between packets
        begin_pkt;
        nclk(20 * L);
        snap; first(8'hA5); send(8'h02, 4); send(8'd1, 4); send(8'h05, 4); send(8'hDC, 4); send(8'h02 ^ 8'd1 ^ 8'h05 ^ 8'hDC, 4); settle;
        check(n_ack == a0 + 1 && active && !failed, "20*TLIM of silence between packets: upload still active, next WRITE accepted");

        // ---- quiet period after a checksum error: leaves exactly when a byte comes TLIM+2 clocks after the last one
        //      (no settle between the error byte and the probe byte, so the distances below are exact)
        snap; first(8'hA5); send(8'h01, 4); send(8'h00, 4);                           // bad CHK -> NAK 1, QUIET
        send(8'hA5, L + 1); send(8'h01, 4); send(8'h01, 4); settle;                   // SOF at distance TLIM+1
        check(n_nak == k0 + 1 && last_err == 4'd1 && n_ack == a0, "bad checksum -> NAK 1; a packet whose SOF is TLIM+1 clocks later is swallowed (no ACK, no 2nd NAK)");
        long_silence;
        snap; first(8'hA5); send(8'h01, 4); send(8'h00, 4);
        send(8'hA5, L + 2); send(8'h01, 4); send(8'h01, 4); settle;                   // SOF at distance TLIM+2
        check(n_nak == k0 + 1 && n_ack == a0 + 1, "a packet whose SOF is TLIM+2 clocks after the error byte is accepted (quiet period over)");

        // ---- QUIET is extended by every byte received inside it
        long_silence;
        snap; first(8'hA5); send(8'h01, 4); send(8'h00, 4);
        send(8'h77, L + 1); send(8'h77, L + 1); send(8'h77, L + 1); send(8'hA5, 4); send(8'h01, 4); send(8'h01, 4); settle;
        check(n_nak == k0 + 1 && n_ack == a0, "bytes every TLIM+1 clocks keep QUIET alive: a packet right behind them is swallowed");
        long_silence;
        snap; begin_pkt; check(n_ack == a0 + 1, "after TLIM+ clocks of true silence the controller accepts packets again");

        // ---- unknown command: QUIET with the same rule
        snap; first(8'hA5); send(8'h7F, 4); send(8'hA5, L + 1); send(8'h01, 4); send(8'h01, 4); settle;
        check(n_nak == k0 + 1 && last_err == 4'd2 && n_ack == a0, "unknown CMD -> NAK 2; SOF at TLIM+1 swallowed");
        long_silence;
        snap; first(8'hA5); send(8'h7F, 4); send(8'hA5, L + 2); send(8'h01, 4); send(8'h01, 4); settle;
        check(n_nak == k0 + 1 && n_ack == a0 + 1, "unknown CMD; SOF at TLIM+2 accepted");

        // ---- UART framing error: same quiet rule, also between packets
        long_silence;
        snap; ferr; send(8'hA5, L + 1); send(8'h01, 4); send(8'h01, 4); settle;
        check(n_nak == k0 + 1 && last_err == 4'd10 && n_ack == a0, "framing error -> NAK 10; SOF at TLIM+1 swallowed");
        long_silence;
        snap; ferr; send(8'hA5, L + 2); send(8'h01, 4); send(8'h01, 4); settle;
        check(n_nak == k0 + 1 && n_ack == a0 + 1, "framing error; SOF at TLIM+2 accepted");

        check(n_swap == 0, "no lut_swap pulse occurred anywhere in this timing test");
        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #(1000.0 * 400 * (L + 50)); $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
