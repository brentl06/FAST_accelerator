`timescale 1ns / 1ps

// Connects bounded FAST selection, framebuffer patch reads, orientation and
// rotated BRIEF. The owner must hold the completed source frame until done.
// One feature transaction at a time; backpressure propagates to selection.
module orb_frontend #(
    parameter FRAME_WIDTH=640, FRAME_HEIGHT=480,
    parameter GRID_COLS=8, GRID_ROWS=6, TOP_N=8
)(
    input wire clk, reset, frame_start, frame_pixels_done,
    input wire kp_valid,
    input wire [9:0] kp_x,
    input wire [8:0] kp_y,
    input wire [7:0] kp_score,
    output wire [9:0] fb_read_x,
    output wire [8:0] fb_read_y,
    output wire fb_read_en,
    input wire fb_read_ready, fb_read_valid,
    input wire [3:0] fb_read_data,
    output wire descriptor_valid,
    input wire descriptor_ready,
    output wire [255:0] descriptor,
    output wire [4:0] angle_bin,
    output reg [9:0] feature_x,
    output reg [8:0] feature_y,
    output reg [7:0] feature_score,
    output reg frame_done,
    output wire busy
);
    wire selected_valid, selected_ready, selection_done, selector_busy;
    wire [9:0] selected_x;
    wire [8:0] selected_y;
    wire [7:0] selected_score;
    // Filter before top-N so un-describable border points don't occupy slots.
    wire usable = kp_x >= 20 && kp_x < FRAME_WIDTH-20 &&
                  kp_y >= 20 && kp_y < FRAME_HEIGHT-20;
    orb_grid_top_n #(.FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT),
        .GRID_COLS(GRID_COLS), .GRID_ROWS(GRID_ROWS), .TOP_N(TOP_N)) selection (
        .clk(clk), .reset(reset), .frame_start(frame_start),
        .frame_done(frame_pixels_done), .kp_valid(kp_valid && usable),
        .kp_x(kp_x), .kp_y(kp_y), .kp_score(kp_score),
        .selected_valid(selected_valid), .selected_ready(selected_ready),
        .selected_x(selected_x), .selected_y(selected_y),
        .selected_score(selected_score), .selection_done(selection_done),
        .busy(selector_busy));
    wire patch_ready, engine_ready;
    wire transaction_start = selected_valid && selected_ready;
    assign selected_ready = patch_ready && engine_ready;
    wire patch_valid, patch_done, patch_rejected;
    wire [3:0] patch_pixel;
    wire [5:0] patch_col, patch_row;
    orb_patch_reader #(.FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT),
        .PATCH_SIZE(41)) reader (
        .clk(clk), .reset(reset), .start(transaction_start),
        .keypoint_x(selected_x), .keypoint_y(selected_y),
        .start_ready(patch_ready), .busy(),
        .fb_read_x(fb_read_x), .fb_read_y(fb_read_y), .fb_read_en(fb_read_en),
        .fb_read_ready(fb_read_ready), .fb_read_valid(fb_read_valid),
        .fb_read_data(fb_read_data), .patch_valid(patch_valid),
        .patch_pixel(patch_pixel), .patch_col(patch_col), .patch_row(patch_row),
        .patch_done(patch_done), .keypoint_rejected(patch_rejected));
    orb_descriptor engine (
        .clk(clk), .reset(reset), .start(transaction_start),
        .patch_valid(patch_valid), .patch_pixel(patch_pixel),
        .patch_col(patch_col), .patch_row(patch_row), .patch_done(patch_done),
        .patch_rejected(patch_rejected), .start_ready(engine_ready),
        .descriptor_valid(descriptor_valid), .descriptor_ready(descriptor_ready),
        .descriptor(descriptor), .angle_bin(angle_bin), .rejected());
    reg active, selection_finished;
    assign busy = active;
    always @(posedge clk) begin
        if (reset) begin
            active <= 0; selection_finished <= 0; frame_done <= 0;
            feature_x <= 0; feature_y <= 0; feature_score <= 0;
        end else begin
            frame_done <= 0;
            if (frame_start) begin active <= 1; selection_finished <= 0; end
            if (transaction_start) begin
                feature_x <= selected_x; feature_y <= selected_y;
                feature_score <= selected_score;
            end
            if (selection_done) selection_finished <= 1;
            if (active && selection_finished && engine_ready && patch_ready &&
                !selected_valid && !selector_busy) begin
                active <= 0; frame_done <= 1; selection_finished <= 0;
            end
        end
    end
endmodule
