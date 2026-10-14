`timescale 1ns / 1ps
// NEGATIVE TEST - this file MUST FAIL to compile/elaborate.
// SCLK_HZ = 2 MHz exceeds the MCP3008 limit at 3.3 V (1.35 MHz).
module tb_adc_bad_param;
    wire       busy, dv, fe, cs_n, sclk, mosi;
    wire [9:0] d;
    wire [2:0] dc;
    adc_spi_interface #(.CLK_HZ(100_000_000), .SCLK_HZ(2_000_000)) dut (
        .clk(1'b0), .rst(1'b1), .start(1'b0), .channel(3'd0),
        .busy(busy), .data(d), .data_channel(dc), .data_valid(dv), .frame_err(fe),
        .spi_cs_n(cs_n), .spi_sclk(sclk), .spi_mosi(mosi), .spi_miso(1'b0)
    );
endmodule
