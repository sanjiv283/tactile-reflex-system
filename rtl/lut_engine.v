`timescale 1ns / 1ps
// Fixed-function FPGA hardware transfer function: ADC value -> servo pulse (us).
// Two banks (double buffer). Reads use the ACTIVE bank; writes go only to the
// INACTIVE bank; 'swap' switches the whole table in one clock cycle.
// The table is constant between swaps -> every sample takes exactly 1 clock.
module lut_engine #(
    parameter INIT_FILE = ""   // optional hex file from lut_gen.py
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [9:0]  adc_value,
    input  wire        adc_valid,
    output reg  [11:0] lut_pulse_us,
    output reg         lut_valid,
    input  wire        wr_en,
    input  wire [5:0]  wr_addr,
    input  wire [11:0] wr_data,
    input  wire        swap,
    output reg         active_bank
);
    reg [11:0] bank0 [0:63];
    reg [11:0] bank1 [0:63];
    integer i;

    // Power-up contents. Placeholder curve (NOT a calibrated result):
    // more force -> smaller pulse -> gripper backs off.
    initial begin
        active_bank = 1'b0;
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, bank0);
            $readmemh(INIT_FILE, bank1);
        end else
            for (i = 0; i < 64; i = i + 1) begin
                bank0[i] = 12'd2000 - i * 16;
                bank1[i] = 12'd2000 - i * 16;
            end
    end

    always @(posedge clk) begin
        if (wr_en &&  active_bank) bank0[wr_addr] <= wr_data;
        if (wr_en && !active_bank) bank1[wr_addr] <= wr_data;
    end

    wire [5:0] idx = adc_value[9:4];   // 64 force levels

    // active_bank is deliberately not reset: a reset keeps the current table.
    always @(posedge clk) begin
        if (swap) active_bank <= ~active_bank;
        if (rst) begin
            lut_valid <= 1'b0; lut_pulse_us <= 0;
        end else begin
            lut_valid <= adc_valid;
            if (adc_valid)
                lut_pulse_us <= active_bank ? bank1[idx] : bank0[idx];
        end
    end
endmodule
