`timescale 1ns/1ps
// Must FAIL to compile: SCLK_HZ above the 1.35 MHz limit.
module tb_adc_bad_param;
    wire cs_n, sclk, mosi, busy, dv, fe; wire [9:0] d;
    adc_spi_interface #(.CLK_HZ(100_000_000), .SCLK_HZ(2_000_000)) dut (
        .clk(1'b0), .rst(1'b1), .start(1'b0), .channel(3'd0), .miso(1'b1),
        .cs_n(cs_n), .sclk(sclk), .mosi(mosi), .busy(busy), .data(d), .data_valid(dv), .frame_err(fe));
endmodule
