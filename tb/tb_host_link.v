`timescale 1ns/1ps
// Host -> board link: the byte stream produced by host/ai_host.build_ai_packet (tb/host_link_bytes.mem, made by tools/gen_host_link_vectors.py)
// is sent over a real uart_tx -> ai_uart_bridge -> ai_control_interface chain. For every 3-byte group the RTL must accept it exactly when the
// expectation file says so, with the right class / complement / valid bit, and a corrupted group must change nothing at all.
module tb_host_link;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    localparam CPB = 16, NG = 48;
    reg [7:0] bytes [0:3*NG+2]; reg [7:0] expect [0:NG];
    reg [7:0] txd_data = 0; reg send = 0; wire busy, line;
    uart_tx #(.CLKS_PER_BIT(CPB)) tx (.clk(clk), .rst_n(rst_n), .data(txd_data), .send(send), .busy(busy), .txd(line));
    wire [15:0] g; ai_uart_bridge #(.CLKS_PER_BIT(CPB)) br (.clk(clk), .rst_n(rst_n), .rxd(line), .ai_gpio(g));
    wire [1:0] ai_class; wire ai_valid; ai_control_interface #(.TIMEOUT(1000000)) aic (.clk(clk), .rst_n(rst_n), .gpio(g), .ai_class(ai_class), .ai_valid(ai_valid));
    integer pass = 0, fail = 0, i, n, accepted_seen = 0, rejected_seen = 0; reg [15:0] g_before; reg [7:0] e;
    task check(input c, input [255:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL: group %0d: %0s", i, msg); end end endtask
    task tx_byte(input [7:0] b); begin @(negedge clk); while (busy) @(negedge clk); txd_data = b; send = 1; @(negedge clk); send = 0; @(negedge clk); while (busy) @(negedge clk); end endtask
    initial begin
        for (i = 0; i < 3*NG+3; i = i + 1) bytes[i] = 8'hxx; for (i = 0; i <= NG; i = i + 1) expect[i] = 8'hxx;
        $readmemh("tb/host_link_bytes.mem", bytes); $readmemh("tb/host_link_expect.mem", expect);
        n = 0; while (n < NG && expect[n] !== 8'hxx) n = n + 1;
        check(n == NG && bytes[3*NG-1] !== 8'hxx && expect[NG] === 8'hxx && bytes[3*NG] === 8'hxx, "vector files hold exactly NG groups (none skipped, none extra)");
        repeat (4) @(posedge clk); rst_n = 1; repeat (4) @(posedge clk);
        for (i = 0; i < n; i = i + 1) begin
            e = expect[i]; g_before = g;
            tx_byte(bytes[3*i]); tx_byte(bytes[3*i+1]); tx_byte(bytes[3*i+2]); repeat (4 * CPB) @(posedge clk);
            if (e[7]) begin
                accepted_seen = accepted_seen + 1;
                check(g[15:8] == g_before[15:8] + 8'd1, "good packet: heartbeat incremented once");
                check(g[1:0] == e[1:0] && g[5:4] == ~e[1:0], "good packet: class and complement");
                check(g[6] == e[4], "good packet: valid bit as sent");
                check(ai_class == e[1:0] && ai_valid == e[4], "good packet: ai_control_interface output (class / valid)");
            end else begin
                rejected_seen = rejected_seen + 1;
                check(g === g_before, "corrupted packet: gpio word completely unchanged");
            end
        end
        check(accepted_seen > 0 && rejected_seen > 0, "both accepted and rejected groups were exercised");
        $display("TB tb_host_link: PASS %0d FAIL %0d VECTORS %0d NOTE host packet builder -> uart_tx -> ai_uart_bridge -> ai_control_interface; %0d accepted, %0d rejected", pass, fail, n, accepted_seen, rejected_seen);
        $finish;
    end
    initial begin #50_000_000; $display("TB tb_host_link: TIMEOUT"); $finish; end
endmodule
