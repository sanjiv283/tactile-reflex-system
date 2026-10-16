`timescale 1ns / 1ps
// NEGATIVE TEST - this file MUST FAIL to compile/elaborate.
// 1 MHz clock at 500 kBd is only 2 clocks per bit (< 8 required).
module tb_uart_tx_bad_param;
    wire ready, tx, busy;
    uart_tx #(.CLK_HZ(1_000_000), .BAUD(500_000)) dut (
        .clk(1'b0), .rst(1'b1), .tx_data(8'h00), .tx_valid(1'b0), .tx_ready(ready), .tx(tx), .busy(busy));
endmodule
