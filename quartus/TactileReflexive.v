`timescale 1ns / 1ps
// DE2-115 board wrapper for the Tactile Reflex System (first hardware milestone: reflex_top_spi, no UART upload).
//
//   MCP3008 --SPI--> adc_spi_interface --> LUT --> safety_governor --> servo PWM       (all inside reflex_top_spi)
//
// reflex_top_spi is the existing, simulated integration of adc_spi_interface and reflex_top: it already connects the
// ADC samples (data/data_valid) to reflex_top, so the safety governor stays in the path. This wrapper only adapts the
// board: clock frequency, push-button polarity, and which header pins carry which signal.
//
// Port names follow Terasic's DE2-115 conventions (CLOCK_50, KEY, SW, LEDR, LEDG, GPIO) so that pin locations can be
// taken from Terasic's own pin-assignment file (see quartus/README_DE2_115.md). NO pin numbers are guessed in this file.
//
// NOT verified on hardware. The LUT is the placeholder curve, not a calibrated gripper table.
module TactileReflexive #(
    parameter FRAME_US = 20_000       // servo frame in us: 20 ms (50 Hz) on the board; only a shorter value is used to speed up simulation
) (
    input  wire        CLOCK_50,      // 50 MHz board clock
    input  wire [3:0]  KEY,           // push-buttons: idle HIGH, pressed = LOW (active low)
    input  wire [17:0] SW,            // slide switches
    output wire [17:0] LEDR,          // red LEDs
    output wire [8:0]  LEDG,          // green LEDs
    inout  wire [35:0] GPIO           // 40-pin expansion header (3.3 V logic)
);
    // ---- GPIO usage (logical GPIO indices; the physical pins come from the board's pin table)
    //   GPIO[0] -> MCP3008 CS/SHDN     GPIO[1] -> MCP3008 CLK     GPIO[2] -> MCP3008 DIN (MOSI)
    //   GPIO[3] <- MCP3008 DOUT (MISO, input, weak pull-up set in the .tcl)     GPIO[4] -> servo signal
    wire spi_cs_n, spi_sclk, spi_mosi, servo_out;
    wire spi_miso = GPIO[3];

    assign GPIO[0] = spi_cs_n;
    assign GPIO[1] = spi_sclk;
    assign GPIO[2] = spi_mosi;
    assign GPIO[3] = 1'bz;            // input
    assign GPIO[4] = servo_out;
    assign GPIO[35:5] = {31{1'bz}};   // unused header pins stay high impedance (inputs)

    // ---- controls (the tops synchronise these asynchronous inputs themselves with 2-flop synchronisers)
    wire rst_btn    = ~KEY[0];        // KEY0 pressed (0) -> reset asserted (active high inside the design)
    wire estop_btn  = ~KEY[1];        // KEY1 pressed (0) -> emergency stop (latched until reset). A board button is NOT a fail-safe e-stop.
    wire grip_en_sw = SW[0];          // SW0 = 1 enables gripping; 0 holds the SAFE pulse. Power-up default is 0 (disabled).

    wire [3:0] fault_led;             // {estop, adc_timeout, adc_range, overforce}
    wire       active_bank_led, dbg_cmd_toggle, adc_frame_err;

    reflex_top_spi #(
        .CLK_HZ        (50_000_000),  // DE2-115 clock; the RTL default is 100 MHz and would be wrong here
        .SCLK_HZ       (1_000_000),   // 1 MHz SPI clock; MCP3008 limit at 3.3 V is about 1.35 MHz
        .FRAME_US      (FRAME_US),    // 50 Hz servo frame by default
        .LUT_INIT_FILE ("")           // built-in placeholder table; set to a generated hex file later
    ) u_reflex (
        .clk            (CLOCK_50),
        .rst_btn        (rst_btn),
        .estop_btn      (estop_btn),
        .grip_en_sw     (grip_en_sw),
        .spi_cs_n       (spi_cs_n),
        .spi_sclk       (spi_sclk),
        .spi_mosi       (spi_mosi),
        .spi_miso       (spi_miso),
        // LUT programming is not used in this milestone: inactive, safe values
        .lut_wr_en      (1'b0),
        .lut_wr_addr    (6'd0),
        .lut_wr_data    (12'd0),
        .lut_swap       (1'b0),
        .servo_out      (servo_out),
        .fault_led      (fault_led),
        .active_bank_led(active_bank_led),
        .dbg_cmd_toggle (dbg_cmd_toggle),
        .adc_frame_err  (adc_frame_err)
    );

    // ---- indicators
    assign LEDR[3:0]  = fault_led;        // LEDR3 e-stop, LEDR2 ADC timeout, LEDR1 ADC range, LEDR0 over-force
    assign LEDR[4]    = adc_frame_err;
    assign LEDR[5]    = dbg_cmd_toggle;
    assign LEDR[17:6] = 12'b0;
    assign LEDG[0]    = servo_out;        // 50 Hz pulse: appears dim
    assign LEDG[1]    = active_bank_led;
    assign LEDG[2]    = rst_btn;          // reset requested
    assign LEDG[3]    = estop_btn;        // e-stop requested
    assign LEDG[8:4]  = 5'b0;
endmodule
