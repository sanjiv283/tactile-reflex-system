`timescale 1ns / 1ps
// SIMULATION ONLY. Independent behavioural 8N1 line decoder used by the Stage 4 testbenches, so
// the transmitter is never checked with its own logic. It waits for a falling edge, samples the
// middle of each bit using BIT_NS, and reports the byte. A frame cut short by a reset (line goes
// idle high) is reported as a byte with the missing bits read as 1, like a real receiver would.
//   valid    : pulses high for 1 ns when a byte has been decoded (use @(posedge valid))
//   n_fe     : stop bit read low
//   t_start  : $realtime of the falling edge of the last start bit (read hierarchically)
module uart_monitor #(
    parameter real BIT_NS = 1000.0
)(
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid,
    output reg [31:0] n_bytes,
    output reg [31:0] n_fe
);
    real    t_start;
    integer i;
    reg [7:0] d;
    initial begin valid = 0; data = 0; n_bytes = 0; n_fe = 0; t_start = 0; end
    always begin
        @(negedge rx);
        t_start = $realtime;
        #(BIT_NS * 1.5);
        for (i = 0; i < 8; i = i + 1) begin d[i] = rx; #(BIT_NS); end
        if (rx !== 1'b1) n_fe = n_fe + 1;
        data = d; n_bytes = n_bytes + 1; valid = 1'b1; #1 valid = 1'b0;
    end
endmodule
