// telemetry_tx: FPGA -> laptop. Every PERIOD clocks send 3 bytes: 0x5A, {flags[3:0], force_code[11:8]}, force_code[7:0].
// flags = {safe_state, sensor_fault, estop_active, ai_valid}. At 50 MHz, PERIOD=50000 is 1 kHz.
module telemetry_tx #(parameter CLKS_PER_BIT = 434, parameter PERIOD = 50000) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] force_code,
    input  wire [3:0]  flags,
    output wire        txd
);
    reg [31:0] pc;
    reg [1:0]  idx;
    reg        active, send;
    reg [7:0]  b1, b2, tx_data;
    wire busy;
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (.clk(clk), .rst_n(rst_n), .data(tx_data), .send(send), .busy(busy), .txd(txd));

    always @(posedge clk) begin
        if (!rst_n) begin
            pc <= 32'd0; idx <= 2'd0; active <= 1'b0; send <= 1'b0; b1 <= 8'd0; b2 <= 8'd0; tx_data <= 8'd0;
        end else begin
            send <= 1'b0;
            if (!active) begin
                if (pc >= PERIOD - 1) begin pc <= 32'd0; active <= 1'b1; idx <= 2'd0; b1 <= {flags, force_code[11:8]}; b2 <= force_code[7:0]; end
                else pc <= pc + 32'd1;
            end else if (!busy && !send) begin
                tx_data <= (idx == 2'd0) ? 8'h5A : (idx == 2'd1) ? b1 : b2;
                send    <= 1'b1;
                idx     <= idx + 2'd1;
                if (idx == 2'd2) active <= 1'b0;
            end
        end
    end
endmodule
