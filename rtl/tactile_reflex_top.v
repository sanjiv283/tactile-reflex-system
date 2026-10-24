// tactile_reflex_top: PL top level. ADC -> conditioning -> fixed LUT -> Safety Governor -> PWM.
// The AI path only enters through ai_control_interface and can only lower the command.
module tactile_reflex_top #(
    parameter CLK_DIV      = 6,
    parameter WD_CYCLES    = 2000,
    parameter AI_TIMEOUT   = 500000,
    parameter [11:0] FORCE_MAX = 12'hA00,
    parameter [11:0] FORCE_REL = 12'h900,
    parameter LUT_FILE     = "rtl/force_lut.mem",
    parameter PRED_EN      = 1,
    parameter PRED_WIN     = 150000,
    parameter PRED_K       = 2,
    parameter [11:0] PRED_MIN_DELTA = 12'd150
) (
    input  wire        clk,
    input  wire        rst_n,
    // ADC (SPI)
    output wire        adc_cs_n,
    output wire        adc_sclk,
    input  wire        adc_miso,
    // switches
    input  wire        estop_n,        // low = stop (normally-closed contact, fail-safe)
    input  wire        fault_clear,
    // from PS
    input  wire [15:0] ai_gpio,
    // outputs
    output wire        pwm_out,
    output wire        safe_state,
    output wire        sensor_fault,
    output wire        estop_active,
    output wire        ai_valid,
    // observation points (logic analyzer / testbench)
    output wire        dbg_sample_valid,
    output wire [11:0] force_out,
    output wire [7:0]  cmd_out,
    output wire [4:0]  trip_reason,
    output wire        ai_overridden
);
    // reset: asynchronous assert, synchronous release
    reg [1:0] rs;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rs <= 2'b00; else rs <= {rs[0], 1'b1};
    end
    wire rst_s = rs[1];

    // input synchronisers
    reg [1:0] es, fc;
    always @(posedge clk) begin
        if (!rst_s) begin es <= 2'b00; fc <= 2'b00; end   // e-stop reads "pressed" during reset
        else begin es <= {es[0], estop_n}; fc <= {fc[0], fault_clear}; end
    end

    wire [11:0] sample; wire sample_valid, frame_err;
    adc_interface #(.CLK_DIV(CLK_DIV)) u_adc (.clk(clk), .rst_n(rst_s), .adc_miso(adc_miso),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk), .sample(sample), .sample_valid(sample_valid), .frame_err(frame_err));
    assign dbg_sample_valid = sample_valid;

    wire [11:0] force_code; wire force_valid, adc_invalid;
    input_conditioning u_cond (.clk(clk), .rst_n(rst_s), .sample(sample), .sample_valid(sample_valid),
        .frame_err(frame_err), .force_code(force_code), .force_valid(force_valid), .adc_invalid(adc_invalid));

    wire [11:0] lut_force; wire [7:0] lut_cmd; wire lut_valid;
    force_lut #(.LUT_FILE(LUT_FILE)) u_lut (.clk(clk), .rst_n(rst_s), .force_code(force_code),
        .force_valid(force_valid), .force_code_o(lut_force), .lut_cmd(lut_cmd), .lut_valid(lut_valid));

    wire [2:0] fault_code;
    fault_handler #(.WD_CYCLES(WD_CYCLES)) u_fault (.clk(clk), .rst_n(rst_s), .sample_valid(force_valid),
        .adc_invalid(adc_invalid), .estop_n(es[1]), .fault_clear(fc[1]),
        .sensor_fault(sensor_fault), .estop_active(estop_active), .fault_code(fault_code));

    wire [1:0] ai_class; wire ai_used;
    ai_control_interface #(.TIMEOUT(AI_TIMEOUT)) u_ai (.clk(clk), .rst_n(rst_s), .gpio(ai_gpio),
        .ai_class(ai_class), .ai_valid(ai_valid));

    safety_governor #(.FORCE_MAX(FORCE_MAX), .FORCE_REL(FORCE_REL), .PRED_EN(PRED_EN), .PRED_WIN(PRED_WIN), .PRED_K(PRED_K), .PRED_MIN_DELTA(PRED_MIN_DELTA)) u_gov (.clk(clk), .rst_n(rst_s),
        .in_valid(lut_valid), .force_code(lut_force), .lut_cmd(lut_cmd), .adc_invalid(adc_invalid),
        .sensor_fault(sensor_fault), .estop_active(estop_active), .ai_valid(ai_valid), .ai_class(ai_class),
        .cmd_out(cmd_out), .safe_state(safe_state), .trip_reason(trip_reason), .ai_used(ai_used),
        .ai_overridden(ai_overridden));

    assign force_out = lut_force;

    pwm_generator u_pwm (.clk(clk), .rst_n(rst_s), .duty(cmd_out), .kill(safe_state), .pwm_out(pwm_out));
endmodule
