// button_debounce: 2-flop synchroniser + stability filter for a MECHANICAL push button (used for the fault-clear key only).
// `pressed` changes only after the synchronised input has differed from it for DEBOUNCE_CLKS consecutive clocks, so contact bounce
// and short glitches never produce an event, and one physical press gives exactly one rising edge of `pressed`.
// press_pulse is ONE clock wide per deliberate press, and only if the button has been seen released since reset: a key that is held
// down through reset, or stuck closed, can therefore never act as a 'clear' (it must be released and pressed again).
// Do NOT use this on the emergency stop: the stop path must stay fast (2-flop synchroniser only) and is latched in fault_handler.
module button_debounce #(
    parameter DEBOUNCE_CLKS = 1000000,   // 20 ms at 50 MHz
    parameter ACTIVE_LOW    = 1          // 1: the button reads 0 when pressed (DE2-115 KEY switches)
) (
    input  wire clk,
    input  wire rst_n,                   // synchronous, active low (use the synchronised reset)
    input  wire btn_raw,                 // asynchronous, from the pin
    output reg  pressed,                 // debounced level, clock-synchronous, active high
    output reg  press_pulse              // 1 clock: debounced press detected (and the button had been released since reset)
);
    reg armed;
    reg [1:0] warm;                      // skips the first 3 clocks after reset: the synchroniser's reset value is a phantom 'released'
    reg [1:0]  s;
    reg [23:0] cnt;
    wire in_pressed = ACTIVE_LOW ? ~s[1] : s[1];
    always @(posedge clk) begin
        if (!rst_n) begin
            s <= ACTIVE_LOW ? 2'b11 : 2'b00; cnt <= 24'd0; pressed <= 1'b0; press_pulse <= 1'b0; armed <= 1'b0; warm <= 2'd0;
        end else begin
            s <= {s[0], btn_raw};
            press_pulse <= 1'b0;
            if (warm != 2'd3) warm <= warm + 2'd1;
            else if (!pressed && !in_pressed) armed <= 1'b1;     // genuinely released at least once since reset
            if (in_pressed == pressed) cnt <= 24'd0;
            else if (cnt >= DEBOUNCE_CLKS - 1) begin pressed <= in_pressed; press_pulse <= in_pressed & armed; cnt <= 24'd0; end
            else cnt <= cnt + 24'd1;
        end
    end
endmodule
