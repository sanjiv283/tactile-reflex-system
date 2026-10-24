// fault_handler: latches e-stop and persistent sensor faults; cleared only by an explicit fault_clear
// once the cause is gone.
module fault_handler #(
    parameter WD_CYCLES     = 2000,  // no ADC sample for this many clocks -> fault
    parameter INVALID_LIMIT = 4      // consecutive invalid samples -> fault
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sample_valid,
    input  wire       adc_invalid,
    input  wire       estop_n,       // synchronised, low = e-stop pressed (or wire cut)
    input  wire       fault_clear,   // synchronised, level
    output reg        sensor_fault,
    output reg        estop_active,
    output reg  [2:0] fault_code     // [0] ADC timeout, [1] persistent invalid, [2] e-stop
);
    reg [15:0] wd_cnt;
    reg [3:0]  bad_cnt;
    wire timeout = (wd_cnt >= WD_CYCLES);
    wire persist = (bad_cnt >= INVALID_LIMIT);

    always @(posedge clk) begin
        if (!rst_n) begin
            wd_cnt <= 16'd0; bad_cnt <= 4'd0; sensor_fault <= 1'b0;
            estop_active <= ~estop_n; fault_code <= 3'd0;
        end else begin
            if (sample_valid) wd_cnt <= 16'd0;
            else if (!timeout) wd_cnt <= wd_cnt + 16'd1;

            if (sample_valid) begin
                if (!adc_invalid) bad_cnt <= 4'd0;
                else if (!persist) bad_cnt <= bad_cnt + 4'd1;
            end

            if (timeout | persist)  sensor_fault <= 1'b1;
            else if (fault_clear)   sensor_fault <= 1'b0;

            if (!estop_n)           estop_active <= 1'b1;
            else if (fault_clear)   estop_active <= 1'b0;

            fault_code <= {~estop_n | estop_active, persist, timeout};
        end
    end
endmodule
