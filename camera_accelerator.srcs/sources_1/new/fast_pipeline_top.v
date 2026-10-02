`timescale 1ns / 1ps

// FAST detector with framebuffer-ready outputs (same write interface as
// processing_pipeline_top). Each position is written once per frame: the
// full-brightness grayscale image plus a separate keypoint marker. Positions
// x = 0..W-5, y = 0..H-5 are written; the last four
// columns and rows are left for the display path to blank.
//
// kp_* is the raw keypoint stream for downstream ORB stages. frame_keypoints
// holds the keypoint count of the last completed frame, also kept as 4-digit
// BCD (saturating at 9999) for the seven-segment display.
module fast_pipeline_top #(
    parameter FRAME_WIDTH  = 640,
    parameter FRAME_HEIGHT = 480
)(
    input  wire        clk,
    input  wire        reset,
    input  wire [7:0]  pixel_in,
    input  wire        pixel_valid,
    input  wire        frame_start,
    input  wire [7:0]  threshold,

    output reg  [3:0]  pixel_out,
    output reg         keypoint_out,
    output reg  [9:0]  x,
    output reg  [8:0]  y,
    output reg         write_en,
    output reg         frame_done,

    output wire        kp_valid,
    output wire [9:0]  kp_x,
    output wire [8:0]  kp_y,
    output wire [7:0]  kp_score,
    output reg  [15:0] frame_keypoints,
    output reg  [15:0] frame_keypoints_bcd
);

    wire       det_valid, det_inside, det_keypoint;
    wire [9:0] det_x;
    wire [8:0] det_y;
    wire [7:0] det_score, det_gray;

    fast_detector #(
        .FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT)
    ) detector (
        .clk(clk), .reset(reset),
        .pixel_in(pixel_in), .pixel_valid(pixel_valid),
        .frame_start(frame_start), .threshold(threshold),
        .out_valid(det_valid), .out_inside(det_inside),
        .out_x(det_x), .out_y(det_y), .out_keypoint(det_keypoint),
        .out_score(det_score), .out_gray(det_gray)
    );

    assign kp_valid = det_valid && det_inside && det_keypoint;
    assign kp_x     = det_x;
    assign kp_y     = det_y;
    assign kp_score = det_score;

    wire last_position = (det_x == FRAME_WIDTH - 5) && (det_y == FRAME_HEIGHT - 5);
    reg [15:0] keypoint_counter;
    reg [15:0] bcd_counter;

    // Saturating 4-digit BCD increment.
    function [15:0] bcd_inc;
        input [15:0] v;
        begin
            if (v == 16'h9999)                bcd_inc = v;
            else if (v[11:0] == 12'h999)      bcd_inc = {v[15:12] + 4'd1, 12'h000};
            else if (v[7:0] == 8'h99)         bcd_inc = {v[15:12], v[11:8] + 4'd1, 8'h00};
            else if (v[3:0] == 4'h9)          bcd_inc = {v[15:8], v[7:4] + 4'd1, 4'h0};
            else                              bcd_inc = {v[15:4], v[3:0] + 4'd1};
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            pixel_out        <= 4'h0;
            keypoint_out     <= 1'b0;
            x                <= 10'd0;
            y                <= 9'd0;
            write_en         <= 1'b0;
            frame_done       <= 1'b0;
            keypoint_counter <= 16'd0;
            frame_keypoints  <= 16'd0;
            bcd_counter      <= 16'd0;
            frame_keypoints_bcd <= 16'd0;
        end else begin
            write_en   <= 1'b0;
            frame_done <= 1'b0;
            keypoint_out <= 1'b0;

            if (det_valid && det_inside) begin
                pixel_out    <= det_gray[7:4];
                keypoint_out <= det_keypoint;
                x         <= det_x;
                y         <= det_y;
                write_en  <= 1'b1;

                if (last_position) begin
                    frame_done       <= 1'b1;
                    frame_keypoints  <= keypoint_counter + det_keypoint;
                    keypoint_counter <= 16'd0;
                    frame_keypoints_bcd <= det_keypoint ? bcd_inc(bcd_counter) : bcd_counter;
                    bcd_counter      <= 16'd0;
                end else if (det_keypoint) begin
                    if (keypoint_counter != 16'hFFFF)
                        keypoint_counter <= keypoint_counter + 1'b1;
                    bcd_counter <= bcd_inc(bcd_counter);
                end
            end
        end
    end

endmodule
