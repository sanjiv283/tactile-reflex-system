`timescale 1ns/1ps
// Behavioural AD7476A-style ADC: value latched at CS fall, MSB-first, 4 leading zeros, next bit on each SCLK fall.
module ad7476_model (input wire cs_n, input wire sclk, input wire [11:0] value, input wire corrupt, output reg miso);
    reg [15:0] frame; integer idx;
    initial miso = 1'b0;
    always @(negedge cs_n) begin frame = {corrupt, 3'b000, value}; idx = 15; miso = frame[15]; end
    always @(negedge sclk) if (!cs_n && idx > 0) begin idx = idx - 1; miso = frame[idx]; end
    always @(posedge cs_n) miso = 1'b0;
endmodule
