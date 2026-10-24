// uart_tx: 8N1 transmitter. Pulse `send` while !busy to start a byte.
module uart_tx #(parameter CLKS_PER_BIT = 434) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       send,
    output reg        busy,
    output reg        txd
);
    reg [3:0]  n;
    reg [15:0] cnt;
    reg [9:0]  sh;      // {stop, data[7:0], start}

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0; txd <= 1'b1; n <= 4'd0; cnt <= 16'd0; sh <= 10'h3FF;
        end else if (!busy) begin
            if (send) begin sh <= {1'b1, data, 1'b0}; busy <= 1'b1; n <= 4'd0; cnt <= 16'd0; txd <= 1'b0; end
        end else if (cnt == CLKS_PER_BIT - 1) begin
            cnt <= 16'd0;
            if (n == 4'd9) begin busy <= 1'b0; txd <= 1'b1; end
            else begin n <= n + 4'd1; txd <= sh[n + 4'd1]; end
        end else cnt <= cnt + 16'd1;
    end
endmodule
