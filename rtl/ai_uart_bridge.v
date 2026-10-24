// ai_uart_bridge: laptop -> FPGA AI message. Packet = 0xA5, DATA, ~DATA.
// DATA[1:0] class, DATA[3:2] ~class, DATA[4] valid. Output uses the ai_control_interface word layout
// (class [1:0], inverse [5:4], valid [6], heartbeat [15:8], incremented once per good packet).
module ai_uart_bridge #(parameter CLKS_PER_BIT = 434) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        rxd,
    output reg  [15:0] ai_gpio
);
    wire [7:0] rb; wire rv;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (.clk(clk), .rst_n(rst_n), .rxd(rxd), .data(rb), .valid(rv));

    reg [1:0] st;
    reg [7:0] d;
    reg [7:0] hb;

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= 2'd0; d <= 8'd0; hb <= 8'd0; ai_gpio <= 16'd0;
        end else if (rv) begin
            case (st)
                2'd0: if (rb == 8'hA5) st <= 2'd1;
                2'd1: begin d <= rb; st <= 2'd2; end
                default: begin
                    st <= 2'd0;
                    if (rb == ~d) begin
                        hb      <= hb + 8'd1;
                        ai_gpio <= {hb + 8'd1, 1'b0, d[4], d[3:2], 2'b00, d[1:0]};
                    end
                end
            endcase
        end
    end
endmodule
