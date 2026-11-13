// fault_handler: latches e-stop and persistent sensor faults. Both latches are cleared TOGETHER, only by a fresh
// release-then-press of fault_clear, and only if every cause is gone (e-stop released, no ADC timeout, no persistent
// invalid). Holding the button never clears anything, and a rejected request is discarded (not remembered).
//
// Clear request (one-cycle pulse clr_req), debounced by CLR_DB clocks of stable input:
//   WAIT  : after reset / after a press; waiting for CLR_DB consecutive low samples            -> ARMED
//   ARMED : released long enough; first high sample                                            -> PRESS (or FIRED if CLR_DB <= 1)
//   PRESS : high for CLR_DB consecutive samples -> FIRED + clr_req pulse; any low sample -> WAIT (bounce: needs a new release)
//   FIRED : request already issued; waits for the button to be released (CLR_DB low samples)   -> ARMED
// Reset starts in WAIT, so a button held through reset is never a fresh press. Fault assertion is not debounced
// and always wins over a clear in the same cycle.
module fault_handler #(
    parameter WD_CYCLES     = 2000,  // no ADC sample for this many clocks -> fault
    parameter INVALID_LIMIT = 4,     // consecutive invalid samples -> fault
    parameter CLR_DB        = 2      // clear-button debounce, clocks of stable input, must be >= 2 (board: 50000 = 1 ms at 50 MHz)
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

    // Parameter guard (elaboration error, never a clamp): CLR_DB >= 2. Same portable mechanism as adc_interface: an invalid
    // value instantiates a module that does not exist, so iverilog, Yosys, Verilator and Quartus all stop with a message that names the rule.
    generate
        if (CLR_DB < 2) begin : bad_clr_db_config
            ERROR_fault_handler_CLR_DB_must_be_at_least_2 invalid_parameters();
        end
    endgenerate

    // ---- clear-button release/press detector ----
    // run counts consecutive samples at the current level and saturates at CLR_DB, so it needs RW = ceil(log2(CLR_DB+1)) bits
    // (CLR_DB=2 -> 2 bits, CLR_DB=50000 -> 16 bits). Constant function: portable Verilog-2001, no $clog2.
    function integer clog2;
        input integer v;
        integer k;
        begin clog2 = 0; for (k = v - 1; k > 0; k = k >> 1) clog2 = clog2 + 1; end
    endfunction
    localparam RW = clog2(((CLR_DB < 2) ? 2 : CLR_DB) + 1);   // an invalid CLR_DB is rejected by the guard above; max() only keeps the width legal
    localparam [1:0] C_WAIT = 2'd0, C_ARMED = 2'd1, C_PRESS = 2'd2, C_FIRED = 2'd3;
    reg [1:0]  cst;
    reg [RW-1:0] run;        // consecutive samples at the current input level, saturating at CLR_DB
    reg        ip;           // previous input level
    reg        clr_req;      // one-cycle clear request
    wire [RW-1:0] nrun = (fault_clear != ip) ? {{(RW-1){1'b0}}, 1'b1} : ((run >= CLR_DB) ? run : run + 1'b1);
    wire        stable = (nrun >= CLR_DB);

    // all causes gone: e-stop input released, no ADC timeout, no persistent invalid
    wire causes_gone = estop_n && !timeout && !persist;

    always @(posedge clk) begin
        if (!rst_n) begin
            cst <= C_WAIT; run <= {RW{1'b0}}; ip <= 1'b0; clr_req <= 1'b0;
        end else begin
            ip <= fault_clear; run <= nrun; clr_req <= 1'b0;
            case (cst)
                C_ARMED: if (fault_clear) begin
                             if (stable) begin cst <= C_FIRED; clr_req <= 1'b1; end else cst <= C_PRESS;
                         end
                C_PRESS: if (fault_clear) begin
                             if (stable) begin cst <= C_FIRED; clr_req <= 1'b1; end
                         end else cst <= stable ? C_ARMED : C_WAIT;
                default: if (!fault_clear) cst <= stable ? C_ARMED : C_WAIT;   // WAIT and FIRED: need a release
            endcase
        end
    end

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

            // clear and set never overlap: a clear needs causes_gone, and every set condition is a cause
            if (timeout | persist)  sensor_fault <= 1'b1;
            else if (clr_req && causes_gone) sensor_fault <= 1'b0;

            if (!estop_n)           estop_active <= 1'b1;
            else if (clr_req && causes_gone) estop_active <= 1'b0;

            fault_code <= {~estop_n | estop_active, persist, timeout};
        end
    end
endmodule
