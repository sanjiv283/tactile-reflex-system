// de2_115_top: Terasic DE2-115 (Cyclone IV E EP4CE115, 50 MHz). AI/ML runs on a laptop over the RS-232 port.
//   KEY[3] reset, KEY[1] fault clear, KEY[0] e-stop (pressed = stop), plus an external NC e-stop on ESTOP_EXT_N.
//   ADC (Pmod AD1 or any AD7476A) and PWM / debug pins are on the 40-pin GPIO header (3.3 V).
module de2_115_top #(
    parameter CLKS_PER_BIT = 434,      // 115200 baud at 50 MHz
    parameter TX_PERIOD    = 50000,    // telemetry every 1 ms
    parameter AI_TIMEOUT   = 500000,   // 10 ms without a valid AI packet -> AI ignored
    parameter LUT_FILE     = "rtl/force_lut.mem",
    parameter PRED_EN      = 1,
    parameter PRED_WIN     = 150000,
    parameter ADC_GAP      = 8,        // 1..256, and >= 64 when IDLE_CHK = 1; other values fail elaboration
    parameter IDLE_CHK     = 0,        // 1 = MISO idle-level check (needs the weak pull-up from the QSF)
    parameter ZERO_FRAMES  = 200000,   // advisory zero-reading LED (LEDG[2]), 0 = off
    parameter CLR_DB       = 50000     // KEY[1] fault-clear debounce: 50000 clocks = 1 ms at 50 MHz
) (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,
    input  wire        UART_RXD,       // from the PC
    output wire        UART_TXD,       // to the PC
    output wire        ADC_CS_N,
    output wire        ADC_SCLK,
    input  wire        ADC_MISO,
    input  wire        ESTOP_EXT_N,    // NC contact to 3.3 V, 10 kOhm pull-down; low = stop
    output wire        PWM_OUT,
    output wire        DBG_SAMPLE_VALID,
    output wire        DBG_SAFE_STATE
);
    wire [15:0] ai_gpio;
    wire [11:0] force_out; wire [7:0] cmd; wire [4:0] trip;
    wire safe, sfault, estop_a, ai_v, ai_ov, pwm, dbg_sv, zrun, rst_s;   // rst_s: KEY[3] synchronised in the core (async assert, sync release)

    ai_uart_bridge #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_bridge (.clk(CLOCK_50), .rst_n(rst_s), .rxd(UART_RXD), .ai_gpio(ai_gpio));

    tactile_reflex_top #(.AI_TIMEOUT(AI_TIMEOUT), .LUT_FILE(LUT_FILE), .PRED_EN(PRED_EN), .PRED_WIN(PRED_WIN),
        .ADC_GAP(ADC_GAP), .IDLE_CHK(IDLE_CHK), .ZERO_FRAMES(ZERO_FRAMES), .CLR_DB(CLR_DB)) u_core (
        .clk(CLOCK_50), .rst_n(KEY[3]), .adc_cs_n(ADC_CS_N), .adc_sclk(ADC_SCLK), .adc_miso(ADC_MISO),
        .estop_n(KEY[0] & ESTOP_EXT_N), .fault_clear(~KEY[1]), .ai_gpio(ai_gpio),
        .pwm_out(pwm), .safe_state(safe), .sensor_fault(sfault), .estop_active(estop_a), .ai_valid(ai_v),
        .dbg_sample_valid(dbg_sv), .force_out(force_out), .cmd_out(cmd), .trip_reason(trip), .ai_overridden(ai_ov), .zero_run(zrun), .rst_sync_n(rst_s));

    telemetry_tx #(.CLKS_PER_BIT(CLKS_PER_BIT), .PERIOD(TX_PERIOD)) u_tele (.clk(CLOCK_50), .rst_n(rst_s),
        .force_code(force_out), .flags({safe, sfault, estop_a, ai_v}), .txd(UART_TXD));

    assign PWM_OUT = pwm; assign DBG_SAMPLE_VALID = dbg_sv; assign DBG_SAFE_STATE = safe;
    assign LEDR = {9'd0, trip, ai_ov, estop_a, sfault, safe};    // [0] safe [1] sensor fault [2] e-stop [3] AI overridden [8:4] trip reason (8 = predicted)
    assign LEDG = {6'd0, zrun, pwm, ai_v};                        // [0] AI valid [1] PWM [2] advisory: long run of zero readings
endmodule
