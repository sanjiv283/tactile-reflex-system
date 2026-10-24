// ai_control_interface: receives the PS-side AI result (e.g. from an AXI GPIO) and decides if it can be trusted.
// gpio[1:0] class, gpio[5:4] must equal ~class, gpio[6] PS says valid, gpio[15:8] heartbeat counter.
// AI is valid only if: PS flag set, class/inverse agree, and the heartbeat changed within TIMEOUT clocks.
module ai_control_interface #(
    parameter TIMEOUT = 500000       // clocks without a heartbeat change (10 ms at 50 MHz)
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] gpio,         // asynchronous to clk
    output reg  [1:0]  ai_class,
    output reg         ai_valid
);
    reg [15:0] g1, g2;
    reg [7:0]  hb_prev;
    reg [31:0] tcnt;

    wire alive     = (tcnt < TIMEOUT);
    wire integrity = (g2[5:4] == ~g2[1:0]);

    always @(posedge clk) begin
        if (!rst_n) begin
            g1 <= 16'd0; g2 <= 16'd0; hb_prev <= 8'd0; tcnt <= TIMEOUT;
            ai_class <= 2'd0; ai_valid <= 1'b0;
        end else begin
            g1 <= gpio; g2 <= g1;
            hb_prev <= g2[15:8];
            if (g2[15:8] != hb_prev) tcnt <= 32'd0;
            else if (tcnt < TIMEOUT) tcnt <= tcnt + 32'd1;
            ai_class <= g2[1:0];
            ai_valid <= g2[6] & integrity & alive;
        end
    end
endmodule
