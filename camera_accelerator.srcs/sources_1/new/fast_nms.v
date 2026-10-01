`timescale 1ns / 1ps

// 3x3 non-maximum suppression on a streamed score map.
//
// A point survives iff its score is nonzero and strictly greater than all 8
// neighbors (OpenCV's rule: equal neighbors suppress each other). Non-corners
// must arrive with score 0.
//
// AUX is stored in the line buffers next to each score and returned for the
// window center (used to carry the center pixel's gray value for display).
// One output per input; the output describes the center, which is one column
// and one row behind the newest input (in_col, in_row in out_tag).
module fast_nms #(
    parameter LINE_W = 640,
    parameter AUX_W  = 8,
    parameter TAG_W  = 1
)(
    input  wire             clk,
    input  wire             reset,
    input  wire             in_valid,
    input  wire [7:0]       in_score,
    input  wire [AUX_W-1:0] in_aux,
    input  wire [9:0]       in_col,
    input  wire [TAG_W-1:0] in_tag,

    output reg              out_valid,
    output reg              out_keypoint,
    output reg  [7:0]       out_score,
    output reg  [AUX_W-1:0] out_aux,
    output reg  [TAG_W-1:0] out_tag
);

    localparam DW = 8 + AUX_W;

    wire              win_valid;
    wire [9*DW-1:0]   win;
    wire [TAG_W-1:0]  win_tag;

    line_window #(
        .N(3), .LINE_W(LINE_W), .DATA_W(DW), .TAG_W(TAG_W)
    ) score_window (
        .clk(clk), .reset(reset),
        .in_valid(in_valid), .in_data({in_aux, in_score}),
        .in_col(in_col), .in_tag(in_tag),
        .out_valid(win_valid), .out_win(win), .out_tag(win_tag)
    );

    wire [7:0] s [0:8];
    genvar g;
    generate
        for (g = 0; g < 9; g = g + 1) begin : unpack
            assign s[g] = win[g*DW +: 8];
        end
    endgenerate

    wire [7:0] c = s[4];
    wire is_max = (c != 8'd0) &&
                  (c > s[0]) && (c > s[1]) && (c > s[2]) &&
                  (c > s[3]) &&               (c > s[5]) &&
                  (c > s[6]) && (c > s[7]) && (c > s[8]);

    always @(posedge clk) begin
        out_keypoint <= is_max;
        out_score    <= c;
        out_aux      <= win[4*DW + 8 +: AUX_W];
        out_tag      <= win_tag;

        if (reset)
            out_valid <= 1'b0;
        else
            out_valid <= win_valid;
    end

endmodule
