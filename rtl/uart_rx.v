// uart_rx: 8N1 receiver. Samples each bit at its centre; a bad stop bit drops the byte.
// After a framing error (stop bit low) and after reset the receiver waits until the line has been high for 4 consecutive clocks before it
// looks for a new start bit, so a break or the tail of a corrupted frame is never decoded as a new frame (found by tb_uart_framing).
// 4 clocks is longer than the phantom 'high' the reset value of the 2-flop input synchroniser shows right after reset release.
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
    reg        wait_idle;         // set after a framing error or reset: ignore the line until it is high again
    wire rx = s[1];

    always @(posedge clk) begin
        if (!rst_n) begin
            s <= 2'b11; st <= 2'd0; cnt <= 16'd0; bi <= 3'd0; sh <= 8'd0; data <= 8'd0; valid <= 1'b0; wait_idle <= 1'b1;
        end else begin
            s <= {s[0], rxd};
            valid <= 1'b0;
            case (st)
                2'd0: if (wait_idle) begin
                          if (!rx) cnt <= 16'd0;
                          else if (cnt == 16'd3) wait_idle <= 1'b0;      // line idle for 4 clocks: re-arm
                          else cnt <= cnt + 16'd1;
                      end else if (!rx) begin cnt <= 16'd0; st <= 2'd1; end
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
                          else begin wait_idle <= 1'b1; cnt <= 16'd0; end  // framing error: resynchronise on the next idle line
                      end else cnt <= cnt + 16'd1;
            endcase
        end
    end
endmodule
