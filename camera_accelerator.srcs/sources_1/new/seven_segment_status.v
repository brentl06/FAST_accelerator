`timescale 1ns / 1ps

// Status display for the left four digits of the Nexys A7 seven-segment bank.
// processing_mode = 0 displays "LIVE"; processing_mode = 1 displays the
// frame-latched Sobel threshold as four zero-padded decimal digits.
// show_count = 1 (FAST mode) additionally drives the right four digits with
// count_bcd, the keypoint count of the last frame. Otherwise they stay dark.
module seven_segment_status #(
    parameter REFRESH_COUNTER_BITS = 18
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        processing_mode,
    input  wire [10:0] threshold,
    input  wire        show_count,
    input  wire [15:0] count_bcd,

    output reg  [6:0]  segments,
    output wire        decimal_point,
    output reg  [7:0]  anodes
);

    reg [REFRESH_COUNTER_BITS-1:0] refresh_counter;
    wire [2:0] digit_select;
    reg [3:0] digit_value;

    wire [3:0] thousands;
    wire [3:0] hundreds;
    wire [3:0] tens;
    wire [3:0] ones;

    localparam [3:0] CHAR_L = 4'd10;
    localparam [3:0] CHAR_I = 4'd11;
    localparam [3:0] CHAR_V = 4'd12;
    localparam [3:0] CHAR_E = 4'd13;

    assign digit_select = refresh_counter[REFRESH_COUNTER_BITS-1 -: 3];
    assign decimal_point = 1'b1; // Active-low decimal point; always off.

    // Threshold is limited to 0-375 by the four switches, so these constant
    // divisions synthesize to small fixed combinational logic.
    assign thousands = threshold / 1000;
    assign hundreds  = (threshold % 1000) / 100;
    assign tens      = (threshold % 100) / 10;
    assign ones      = threshold % 10;

    always @(posedge clk) begin
        if (reset)
            refresh_counter <= 0;
        else
            refresh_counter <= refresh_counter + 1'b1;
    end

    always @* begin
        // All digits are off by default. AN7-AN4 are the physical left half,
        // AN3-AN0 the right half. digit_select scans AN0..AN7.
        anodes = 8'hFF;
        if (digit_select[2] || show_count)
            anodes[digit_select] = 1'b0;

        if (!digit_select[2]) begin
            // Right half: keypoint count, AN0 = ones.
            case (digit_select[1:0])
                2'd0: digit_value = count_bcd[3:0];
                2'd1: digit_value = count_bcd[7:4];
                2'd2: digit_value = count_bcd[11:8];
                default: digit_value = count_bcd[15:12];
            endcase
        end else if (processing_mode) begin
            case (digit_select[1:0])
                2'd0: digit_value = ones;      // AN4: rightmost selected digit
                2'd1: digit_value = tens;      // AN5
                2'd2: digit_value = hundreds;  // AN6
                default: digit_value = thousands; // AN7: leftmost digit
            endcase
        end else begin
            // Physical left-to-right order is AN7, AN6, AN5, AN4.
            case (digit_select[1:0])
                2'd0: digit_value = CHAR_E;
                2'd1: digit_value = CHAR_V;
                2'd2: digit_value = CHAR_I;
                default: digit_value = CHAR_L;
            endcase
        end

        // Segments and anodes are active low. Bit order is A,B,C,D,E,F,G.
        case (digit_value)
            4'd0: segments = 7'b0000001;
            4'd1: segments = 7'b1001111;
            4'd2: segments = 7'b0010010;
            4'd3: segments = 7'b0000110;
            4'd4: segments = 7'b1001100;
            4'd5: segments = 7'b0100100;
            4'd6: segments = 7'b0100000;
            4'd7: segments = 7'b0001111;
            4'd8: segments = 7'b0000000;
            4'd9: segments = 7'b0000100;
            CHAR_L: segments = 7'b1110001;
            CHAR_I: segments = 7'b1001111;
            CHAR_V: segments = 7'b1100011;
            CHAR_E: segments = 7'b0110000;
            default: segments = 7'b1111111;
        endcase
    end

endmodule
