`timescale 1ns / 1ps
// NEGATIVE TEST - this file MUST FAIL to compile/elaborate.
// 1 MHz clock at 500 kBd is only 2 clocks per bit (< 8 required).
module tb_uart_bad_param;
    wire [7:0] d; wire v, fe, b;
    uart_rx #(.CLK_HZ(1_000_000), .BAUD(500_000)) dut (
        .clk(1'b0), .rst(1'b1), .rx(1'b1), .data(d), .valid(v), .frame_err(fe), .busy(b));
endmodule
