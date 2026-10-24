// force_lut: fixed-function hardware transfer function, force code -> actuator command (PWM duty).
// The table is loaded at configuration time and is constant during runtime. 256 entries, index = force_code[11:4].
module force_lut #(
    parameter LUT_FILE = "rtl/force_lut.mem"
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] force_code,
    input  wire        force_valid,
    output reg  [11:0] force_code_o,   // force_code aligned with lut_cmd
    output reg  [7:0]  lut_cmd,
    output reg         lut_valid
);
    reg [7:0] rom [0:255];
    initial $readmemh(LUT_FILE, rom);

    always @(posedge clk) begin
        if (!rst_n) begin
            force_code_o <= 12'd0; lut_cmd <= 8'd0; lut_valid <= 1'b0;
        end else begin
            lut_valid <= force_valid;
            if (force_valid) begin
                force_code_o <= force_code;
                lut_cmd      <= rom[force_code[11:4]];
            end
        end
    end
endmodule
