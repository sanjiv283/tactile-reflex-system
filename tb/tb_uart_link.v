`timescale 1ns/1ps
// uart_tx -> uart_rx loopback, and ai_uart_bridge packet parsing (good, corrupt, garbage, resync).
module tb_uart_link;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    localparam CPB = 16;
    reg [7:0] txd_data = 0; reg send = 0; wire busy, line; wire [7:0] rb; wire rv;
    uart_tx #(.CLKS_PER_BIT(CPB)) tx (.clk(clk), .rst_n(rst_n), .data(txd_data), .send(send), .busy(busy), .txd(line));
    uart_rx #(.CLKS_PER_BIT(CPB)) rx (.clk(clk), .rst_n(rst_n), .rxd(line), .data(rb), .valid(rv));
    wire [15:0] g; ai_uart_bridge #(.CLKS_PER_BIT(CPB)) br (.clk(clk), .rst_n(rst_n), .rxd(line), .ai_gpio(g));
    integer pass = 0, fail = 0, i; reg [7:0] got; reg got_v;
    task check(input c, input [255:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL: %0s", msg); end end endtask
    always @(posedge clk) if (rv) begin got <= rb; got_v <= 1; end
    task tx_byte(input [7:0] b); begin @(negedge clk); while (busy) @(negedge clk); txd_data = b; send = 1; @(negedge clk); send = 0; @(negedge clk); while (busy) @(negedge clk); end endtask
    task packet(input [7:0] data, input [7:0] chk); begin tx_byte(8'hA5); tx_byte(data); tx_byte(chk); repeat (4 * CPB) @(posedge clk); end endtask
    initial begin
        repeat (4) @(posedge clk); rst_n = 1; repeat (4) @(posedge clk);
        for (i = 0; i < 6; i = i + 1) begin got_v = 0; tx_byte(i == 0 ? 8'h00 : i == 1 ? 8'hFF : i == 2 ? 8'hA5 : i == 3 ? 8'h5A : i == 4 ? 8'h81 : 8'h16);
            repeat (2 * CPB) @(posedge clk); check(got_v && got == (i == 0 ? 8'h00 : i == 1 ? 8'hFF : i == 2 ? 8'hA5 : i == 3 ? 8'h5A : i == 4 ? 8'h81 : 8'h16), "loopback byte"); end
        check(g == 16'h0000, "no packet yet: idle word");
        packet(8'h16, 8'hE9);   check(g[1:0] == 2'd2 && g[5:4] == 2'b01 && g[6] == 1 && g[15:8] == 8'd1, "class 2 packet accepted, heartbeat 1");
        packet(8'h13, 8'hEC); check(g[1:0] == 2'd3 && g[5:4] == 2'b00 && g[6] == 1 && g[15:8] == 8'd2, "class 3 packet accepted, heartbeat 2");
        packet(8'h1C, 8'hE3);   check(g[1:0] == 2'd0 && g[5:4] == 2'b11 && g[15:8] == 8'd3, "class 0 packet accepted");
        packet(8'h19, 8'hE6);   check(g[1:0] == 2'd1 && g[5:4] == 2'b10 && g[15:8] == 8'd4, "class 1 packet accepted");
        packet(8'h16, 8'h00);   check(g[15:8] == 8'd4 && g[1:0] == 2'd1, "bad checksum ignored");
        tx_byte(8'h33); tx_byte(8'h77); packet(8'h13, 8'hEC); check(g[15:8] == 8'd5 && g[1:0] == 2'd3, "garbage before header: resyncs");
        tx_byte(8'hA5); tx_byte(8'h16); packet(8'h1C, 8'hE3); packet(8'h1C, 8'hE3); check(g[15:8] >= 8'd6 && g[1:0] == 2'd0, "dropped byte: resyncs within one packet");
        rst_n = 0; repeat (3) @(posedge clk); #1 check(g == 16'h0000, "reset clears");
        $display("TB tb_uart_link: PASS %0d FAIL %0d", pass, fail); $finish;
    end
endmodule
