`timescale 1ns/1ps
module tb_force_lut;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    reg [11:0] fc = 0; reg fv = 0; wire [11:0] fco; wire [7:0] cmd; wire lv;
    force_lut dut (.clk(clk), .rst_n(rst_n), .force_code(fc), .force_valid(fv), .force_code_o(fco), .lut_cmd(cmd), .lut_valid(lv));
    integer pass = 0, fail = 0, i, prev, mono_ok;
    task check(input c, input [255:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL: %0s", msg); end end endtask
    task look(input [11:0] code); begin @(negedge clk); fc = code; fv = 1; @(negedge clk); fv = 0; @(negedge clk); end endtask
    initial begin
        repeat (3) @(posedge clk); rst_n = 1;
        look(12'h000); check(cmd == 8'd180, "idx 0 -> 180 (no contact, full approach drive)");
        look(12'h07F); check(cmd == 8'd180, "idx 7 (last of flat region) -> 180");
        look(12'h080); check(cmd == 8'd180, "idx 8 (start of ramp) -> 180");
        look(12'h600); check(cmd == 8'd60, "idx 96 -> 60 (hold level)");
        look(12'h9FF); check(cmd == 8'd1 || cmd == 8'd0, "idx 159 -> last ramp step");
        look(12'hA00); check(cmd == 8'd0, "idx 160 (= FORCE_MAX) -> 0");
        look(12'hFFF); check(cmd == 8'd0, "idx 255 -> 0");
        look(12'h00F); check(cmd == 8'd180, "low nibble ignored: idx stays 0");
        look(12'h010); check(cmd == 8'd180, "idx 1");
        // monotonic non-increasing over the whole table
        prev = 255; mono_ok = 1;
        for (i = 0; i < 256; i = i + 1) begin look({i[7:0], 4'h0}); if (cmd > prev) mono_ok = 0; prev = cmd; end
        check(mono_ok == 1, "transfer function never increases with force");
        look(12'h123); check(fco == 12'h123, "force_code passes through aligned with the command");
        rst_n = 0; @(posedge clk); @(posedge clk); check(cmd == 0 && lv == 0, "reset clears outputs");
        $display("TB tb_force_lut: PASS %0d FAIL %0d", pass, fail); $finish;
    end
endmodule
