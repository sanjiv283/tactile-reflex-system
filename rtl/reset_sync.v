// reset_sync: asynchronous assert, synchronous release. All state that uses the result sees a reset that is
// (a) applied immediately when the button is pressed (even if the pulse is shorter than a clock), and
// (b) released only in step with clk, so no flip-flop can see the reset release violate its recovery time.
// Active-low on both sides. The reset is deliberately NOT debounced: a bouncing reset only re-applies the safe state.
module reset_sync #(parameter STAGES = 2) (
    input  wire clk,
    input  wire arst_n,     // raw, asynchronous, active low (e.g. a push button)
    output wire rst_n       // synchronised, active low
);
    reg [STAGES-1:0] sr;
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) sr <= {STAGES{1'b0}};
        else         sr <= {sr[STAGES-2:0], 1'b1};
    end
    assign rst_n = sr[STAGES-1];
endmodule
