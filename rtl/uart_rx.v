// uart_rx: 8N1 receiver. Samples each bit at its centre; a bad stop bit drops the byte.
module uart_rx #(parameter CLKS_PER_BIT = 434) (   // 50 MHz / 115200
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rxd,
    output reg  [7:0] data,
    output reg        valid       // 1-cycle pulse
);
    reg [1:0]  s;
    reg [1:0]  st;                // 0 idle, 1 start, 2 data, 3 stop
    reg [15:0] cnt;
    reg [2:0]  bi;
    reg [7:0]  sh;
    wire rx = s[1];

    always @(posedge clk) begin
        if (!rst_n) begin
            s <= 2'b11; st <= 2'd0; cnt <= 16'd0; bi <= 3'd0; sh <= 8'd0; data <= 8'd0; valid <= 1'b0;
        end else begin
            s <= {s[0], rxd};
            valid <= 1'b0;
            case (st)
                2'd0: if (!rx) begin cnt <= 16'd0; st <= 2'd1; end
                2'd1: if (cnt == CLKS_PER_BIT / 2 - 1) begin
                          cnt <= 16'd0;
                          if (!rx) begin bi <= 3'd0; st <= 2'd2; end else st <= 2'd0;
                      end else cnt <= cnt + 16'd1;
                2'd2: if (cnt == CLKS_PER_BIT - 1) begin
                          cnt <= 16'd0; sh <= {rx, sh[7:1]};
                          if (bi == 3'd7) st <= 2'd3; else bi <= bi + 3'd1;
                      end else cnt <= cnt + 16'd1;
                2'd3: if (cnt == CLKS_PER_BIT - 1) begin
                          st <= 2'd0;
                          if (rx) begin data <= sh; valid <= 1'b1; end
                      end else cnt <= cnt + 16'd1;
            endcase
        end
    end
endmodule
