`timescale 1ns / 1ps

// FAST-9 segment test and corner score on a 7x7 window.
//
// The 16 pixels on a radius-3 Bresenham circle are compared with the center
// Ip. For each polarity the score is
//     S = max over the 16 arcs of 9 contiguous pixels of
//         min over the arc of (I_k - Ip)    (brighter)  or  (Ip - I_k)  (darker)
// and the pixel is a corner iff S > threshold, which is exactly the FAST-9
// test "9 contiguous pixels all brighter than Ip+t or all darker than Ip-t".
// OpenCV's FAST score is S - 1, so non-max suppression orders points the same.
//
// out_score is S for corners and 0 otherwise (a corner always has S >= 1).
//
// Fully pipelined, one window per clock, latency 8. Data and valid advance
// every clock; the tag and the threshold travel with the data so a threshold
// change can never apply to half a window's pipeline.
module fast_score #(
    parameter TAG_W = 1
)(
    input  wire             clk,
    input  wire             reset,
    input  wire             in_valid,
    input  wire [7*7*8-1:0] in_win,     // line_window layout, N = 7
    input  wire [7:0]       threshold,
    input  wire [TAG_W-1:0] in_tag,

    output wire             out_valid,
    output reg  [7:0]       out_score,
    output wire [TAG_W-1:0] out_tag
);

    localparam LAT = 8;

    function [7:0] min8;
        input [7:0] a, b;
        min8 = (a < b) ? a : b;
    endfunction

    function [7:0] max8;
        input [7:0] a, b;
        max8 = (a > b) ? a : b;
    endfunction

    // Pixel at offset (dx, dy) from the window center.
    function [7:0] px;
        input [7*7*8-1:0] win;
        input integer dx, dy;
        px = win[((3 + dy)*7 + (3 + dx))*8 +: 8];
    endfunction

    // Circle in contiguous (clockwise from top) order.
    wire [7:0] ring [0:15];
    assign ring[0]  = px(in_win,  0, -3);
    assign ring[1]  = px(in_win,  1, -3);
    assign ring[2]  = px(in_win,  2, -2);
    assign ring[3]  = px(in_win,  3, -1);
    assign ring[4]  = px(in_win,  3,  0);
    assign ring[5]  = px(in_win,  3,  1);
    assign ring[6]  = px(in_win,  2,  2);
    assign ring[7]  = px(in_win,  1,  3);
    assign ring[8]  = px(in_win,  0,  3);
    assign ring[9]  = px(in_win, -1,  3);
    assign ring[10] = px(in_win, -2,  2);
    assign ring[11] = px(in_win, -3,  1);
    assign ring[12] = px(in_win, -3,  0);
    assign ring[13] = px(in_win, -3, -1);
    assign ring[14] = px(in_win, -2, -2);
    assign ring[15] = px(in_win, -1, -3);
    wire [7:0] center = px(in_win, 0, 0);

    // Polarity p = 0 brighter, p = 1 darker. Arrays indexed [p*16 + k].
    reg [7:0] d   [0:31];   // stage 1: clamped differences
    reg [7:0] m2  [0:31];   // stage 2: min of ring[k..k+1]
    reg [7:0] m4  [0:31];   // stage 3: min of ring[k..k+3]
    reg [7:0] m8  [0:31];   // stage 4: min of ring[k..k+7]
    reg [7:0] m9  [0:31];   // stage 5: min of ring[k..k+8]  (one 9-arc each)
    reg [7:0] r4  [0:7];    // stage 6: max over groups of 4 arcs
    reg [7:0] s_b, s_d;     // stage 7: best arc per polarity

    // Valid, tag and threshold delay lines matching the datapath.
    reg [LAT-1:0]       valid_pipe;
    reg [TAG_W+8-1:0]   side_pipe [0:LAT-1];
    wire [7:0]          thr_at_end = side_pipe[LAT-2][7:0];

    integer k, p;
    always @(posedge clk) begin
        for (k = 0; k < 16; k = k + 1) begin
            d[k]      <= (ring[k] > center) ? ring[k] - center : 8'd0;
            d[16 + k] <= (center > ring[k]) ? center - ring[k] : 8'd0;
        end

        for (p = 0; p < 2; p = p + 1)
            for (k = 0; k < 16; k = k + 1) begin
                m2[p*16 + k] <= min8(d [p*16 + k], d [p*16 + ((k + 1) % 16)]);
                m4[p*16 + k] <= min8(m2[p*16 + k], m2[p*16 + ((k + 2) % 16)]);
                m8[p*16 + k] <= min8(m4[p*16 + k], m4[p*16 + ((k + 4) % 16)]);
                m9[p*16 + k] <= min8(m8[p*16 + k], m8[p*16 + ((k + 1) % 16)]);
            end

        for (k = 0; k < 8; k = k + 1)
            r4[k] <= max8(max8(m9[4*k], m9[4*k + 1]), max8(m9[4*k + 2], m9[4*k + 3]));

        s_b <= max8(max8(r4[0], r4[1]), max8(r4[2], r4[3]));
        s_d <= max8(max8(r4[4], r4[5]), max8(r4[6], r4[7]));

        // Stage 8: threshold here uses the value that entered with this window.
        out_score <= (max8(s_b, s_d) > thr_at_end) ? max8(s_b, s_d) : 8'd0;
    end

    always @(posedge clk) begin
        side_pipe[0] <= {in_tag, threshold};
        for (k = 1; k < LAT; k = k + 1)
            side_pipe[k] <= side_pipe[k-1];

        if (reset)
            valid_pipe <= 0;
        else
            valid_pipe <= {valid_pipe[LAT-2:0], in_valid};
    end

    assign out_valid = valid_pipe[LAT-1];
    assign out_tag   = side_pipe[LAT-1][TAG_W+8-1:8];

endmodule
