`timescale 1ns / 1ps

// Runs the raw, Sobel and FAST pipelines in parallel and selects one complete
// frame at a time. The mode switches are synchronized here because they come
// from board switches rather than the system clock domain.
//
// active_mode: 0 = raw grayscale, 1 = Sobel edges, 2 = FAST keypoint overlay.
module runtime_pipeline_selector #(
    parameter FRAME_WIDTH = 640,
    parameter FRAME_HEIGHT = 480
)(
    input  wire [7:0] pixel_in,
    input  wire       pixel_valid,
    input  wire       frame_start,
    input  wire       mode_select,
    input  wire       fast_select,
    input  wire [3:0] threshold_select,
    input  wire       clk,
    input  wire       reset,

    output wire [3:0] pixel_out,
    output wire [9:0] x,
    output wire [8:0] y,
    output wire       write_en,
    output wire       frame_done,
    output reg  [1:0] active_mode,
    output reg        mode_changed,
    output reg [10:0] active_threshold,

    // FAST keypoint stream (valid in every mode) and per-frame counts
    output wire       kp_valid,
    output wire [9:0] kp_x,
    output wire [8:0] kp_y,
    output wire [7:0] kp_score,
    output wire [15:0] frame_keypoints,
    output wire [15:0] frame_keypoints_bcd
);

    localparam [1:0] MODE_RAW   = 2'd0;
    localparam [1:0] MODE_SOBEL = 2'd1;
    localparam [1:0] MODE_FAST  = 2'd2;

    // SW2 = 1 selects FAST (overrides SW1); otherwise SW1 = 0 selects raw
    // grayscale and SW1 = 1 selects Sobel edges.
    (* ASYNC_REG = "TRUE" *) reg [1:0] mode_select_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] fast_select_sync;
    (* ASYNC_REG = "TRUE" *) reg [3:0] threshold_select_meta;
    (* ASYNC_REG = "TRUE" *) reg [3:0] threshold_select_sync;

    wire [3:0] raw_pixel_out;
    wire [9:0] raw_x;
    wire [8:0] raw_y;
    wire       raw_write_en;
    wire       raw_frame_done;

    wire [3:0] edge_pixel_out;
    wire [9:0] edge_x;
    wire [8:0] edge_y;
    wire       edge_write_en;
    wire       edge_frame_done;

    wire [3:0] fast_pixel_out;
    wire [9:0] fast_x;
    wire [8:0] fast_y;
    wire       fast_write_en;
    wire       fast_frame_done;
    reg  [7:0] fast_threshold;

    wire [1:0] requested_mode = fast_select_sync[1] ? MODE_FAST :
                                mode_select_sync[1] ? MODE_SOBEL : MODE_RAW;
    function [10:0] threshold_from_switches;
        input [3:0] switch_value;
        begin
            threshold_from_switches = switch_value * 11'd25;
        end
    endfunction

    // FAST threshold: 5, 10, ..., 80. Zero is excluded because it would mark
    // nearly every textured pixel as a corner.
    function [7:0] fast_threshold_from_switches;
        input [3:0] switch_value;
        begin
            fast_threshold_from_switches = (switch_value + 8'd1) * 8'd5;
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            mode_select_sync <= 2'b00;
            fast_select_sync <= 2'b00;
            threshold_select_meta <= 4'b0000;
            threshold_select_sync <= 4'b0000;
        end else begin
            mode_select_sync <= {mode_select_sync[0], mode_select};
            fast_select_sync <= {fast_select_sync[0], fast_select};
            threshold_select_meta <= threshold_select;
            threshold_select_sync <= threshold_select_meta;
        end
    end

    // A physical switch may move at any time, but the framebuffer source must
    // not change partway through a frame. Capture the requested mode only when
    // the camera marks the first pixel of a new frame.
    always @(posedge clk) begin
        if (reset) begin
            active_mode <= MODE_RAW;
            mode_changed <= 1'b0;
            active_threshold <= 11'd0;
            fast_threshold <= 8'd5;
        end else begin
            mode_changed <= 1'b0;

            // The FAST threshold is latched every frame in every mode so the
            // FAST branch is always running with a sane value.
            if (frame_start) begin
                fast_threshold <= fast_threshold_from_switches(threshold_select_sync);
                active_threshold <= (requested_mode == MODE_FAST) ?
                    {3'b000, fast_threshold_from_switches(threshold_select_sync)} :
                    threshold_from_switches(threshold_select_sync);
            end

            if (frame_start && (active_mode != requested_mode)) begin
                active_mode <= requested_mode;
                mode_changed <= 1'b1;
            end
        end
    end

    test_pipeline #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) raw_pipeline (
        .pixel_in(pixel_in),
        .pixel_valid(pixel_valid),
        .frame_start(frame_start),
        .clk(clk),
        .reset(reset),
        .pixel_out(raw_pixel_out),
        .x(raw_x),
        .y(raw_y),
        .write_en(raw_write_en),
        .frame_done(raw_frame_done)
    );

    processing_pipeline_top #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) edge_pipeline (
        .pixel_in(pixel_in),
        .pixel_valid(pixel_valid),
        .frame_start(frame_start),
        .edge_threshold(active_threshold),
        .clk(clk),
        .reset(reset),
        .pixel_out(edge_pixel_out),
        .x(edge_x),
        .y(edge_y),
        .write_en(edge_write_en),
        .frame_done(edge_frame_done)
    );

    // fast_threshold changes on the same clock as frame_start's pixel enters;
    // fast_score carries the threshold with each window, so a frame is always
    // judged with one threshold.
    fast_pipeline_top #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) fast_pipeline (
        .clk(clk),
        .reset(reset),
        .pixel_in(pixel_in),
        .pixel_valid(pixel_valid),
        .frame_start(frame_start),
        .threshold(frame_start ? fast_threshold_from_switches(threshold_select_sync)
                               : fast_threshold),
        .pixel_out(fast_pixel_out),
        .x(fast_x),
        .y(fast_y),
        .write_en(fast_write_en),
        .frame_done(fast_frame_done),
        .kp_valid(kp_valid),
        .kp_x(kp_x),
        .kp_y(kp_y),
        .kp_score(kp_score),
        .frame_keypoints(frame_keypoints),
        .frame_keypoints_bcd(frame_keypoints_bcd)
    );

    // Only the selected branch reaches the framebuffer write port. All
    // branches continue running so each is aligned and ready next frame.
    assign pixel_out  = (active_mode == MODE_FAST)  ? fast_pixel_out :
                        (active_mode == MODE_SOBEL) ? edge_pixel_out : raw_pixel_out;
    assign x          = (active_mode == MODE_FAST)  ? fast_x :
                        (active_mode == MODE_SOBEL) ? edge_x : raw_x;
    assign y          = (active_mode == MODE_FAST)  ? fast_y :
                        (active_mode == MODE_SOBEL) ? edge_y : raw_y;
    assign write_en   = (active_mode == MODE_FAST)  ? fast_write_en :
                        (active_mode == MODE_SOBEL) ? edge_write_en : raw_write_en;
    assign frame_done = (active_mode == MODE_FAST)  ? fast_frame_done :
                        (active_mode == MODE_SOBEL) ? edge_frame_done : raw_frame_done;

endmodule
