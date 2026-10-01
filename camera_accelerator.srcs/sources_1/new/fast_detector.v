`timescale 1ns / 1ps

// FAST-9 corner detector with 3x3 non-maximum suppression.
//
//   pixels -> 7x7 line_window -> fast_score -> fast_nms -> one result/pixel
//
// Every input pixel yields exactly one output, describing image position
// (out_x, out_y) = (col - 4, row - 4) of the newest input pixel at that time.
// out_inside says that position exists (col >= 4 and row >= 4). Outputs are
// in raster order and cover x = 0..W-5, y = 0..H-5; the last 4 columns and
// rows would need pixels after the end of the frame.
//
// Keypoints can appear at x = 3..W-5, y = 3..H-5. This matches OpenCV
// FAST(type 9_16, nonmaxSuppression) except that OpenCV can also report the
// final FAST column/row (x = W-4, y = H-4), which this streaming design omits.
//
// Coordinates travel through the pipeline as tags, so no latency is counted.
module fast_detector #(
    parameter FRAME_WIDTH  = 640,
    parameter FRAME_HEIGHT = 480
)(
    input  wire       clk,
    input  wire       reset,
    input  wire [7:0] pixel_in,
    input  wire       pixel_valid,
    input  wire       frame_start,   // accompanies the first pixel of a frame
    input  wire [7:0] threshold,

    output wire       out_valid,
    output wire       out_inside,
    output wire [9:0] out_x,
    output wire [8:0] out_y,
    output wire       out_keypoint,
    output wire [7:0] out_score,
    output wire [7:0] out_gray       // input pixel at (out_x, out_y)
);

    // Raster position of the incoming pixel. frame_start forces (0, 0).
    reg  [9:0] col_count;
    reg  [8:0] row_count;
    wire [9:0] col = frame_start ? 10'd0 : col_count;
    wire [8:0] row = frame_start ? 9'd0  : row_count;

    always @(posedge clk) begin
        if (reset) begin
            col_count <= 0;
            row_count <= 0;
        end else if (pixel_valid) begin
            if (col == FRAME_WIDTH - 1) begin
                col_count <= 0;
                row_count <= (row == FRAME_HEIGHT - 1) ? 9'd0 : row + 1'b1;
            end else begin
                col_count <= col + 1'b1;
                row_count <= row;
            end
        end
    end

    // 7x7 window
    wire             win_valid;
    wire [7*7*8-1:0] win;
    wire [18:0]      win_pos;      // {col, row} of the newest pixel

    line_window #(
        .N(7), .LINE_W(FRAME_WIDTH), .DATA_W(8), .TAG_W(19)
    ) pixel_window (
        .clk(clk), .reset(reset),
        .in_valid(pixel_valid), .in_data(pixel_in),
        .in_col(col), .in_tag({col, row}),
        .out_valid(win_valid), .out_win(win), .out_tag(win_pos)
    );

    // FAST score of the window center (col - 3, row - 3)
    wire        z_valid;
    wire [7:0]  z_raw;
    wire [26:0] z_tag;             // {col, row, center gray}

    fast_score #(.TAG_W(27)) score (
        .clk(clk), .reset(reset),
        .in_valid(win_valid), .in_win(win), .threshold(threshold),
        .in_tag({win_pos, win[24*8 +: 8]}),
        .out_valid(z_valid), .out_score(z_raw), .out_tag(z_tag)
    );

    wire [9:0] z_col  = z_tag[26:17];
    wire [8:0] z_row  = z_tag[16:8];
    wire [7:0] z_gray = z_tag[7:0];

    // The window is a real image neighborhood only once 7 columns and 7 rows
    // of this frame have arrived; otherwise the center is not a FAST
    // candidate and must enter NMS as score 0.
    wire [7:0] z_score = ((z_col >= 6) && (z_row >= 6)) ? z_raw : 8'd0;

    // NMS over the score map. Its center is one column/row behind z.
    // A nonzero center implies all 8 neighbors come from this frame and row,
    // so no extra edge masking is needed.
    wire [18:0] nms_pos;

    fast_nms #(
        .LINE_W(FRAME_WIDTH), .AUX_W(8), .TAG_W(19)
    ) nms (
        .clk(clk), .reset(reset),
        .in_valid(z_valid), .in_score(z_score), .in_aux(z_gray),
        .in_col(z_col), .in_tag({z_col, z_row}),
        .out_valid(out_valid), .out_keypoint(out_keypoint),
        .out_score(out_score), .out_aux(out_gray), .out_tag(nms_pos)
    );

    wire [9:0] nms_col = nms_pos[18:9];
    wire [8:0] nms_row = nms_pos[8:0];

    assign out_inside = (nms_col >= 4) && (nms_row >= 4);
    assign out_x      = nms_col - 10'd4;
    assign out_y      = nms_row - 9'd4;

endmodule
