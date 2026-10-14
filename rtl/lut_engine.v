// Force -> servo pulse lookup. 1024 entries, 1 clock read latency, holds when en=0.
// Table: pulse_us = 2000 - adc (full open at no force, closing 1 us per ADC count).
// Same table as lut_gen.py.
module lut_engine (
    input             clk,
    input             en,
    input      [9:0]  addr,
    output reg [11:0] q
);
    reg [11:0] mem [0:1023];
    integer i;
    initial for (i = 0; i < 1024; i = i + 1) mem[i] = 2000 - i;
    always @(posedge clk) if (en) q <= mem[addr];
endmodule
