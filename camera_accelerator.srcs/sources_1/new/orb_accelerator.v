`timescale 1ns / 1ps

// Camera-stream integration top. Instantiate beside OV7670_interface, using
// its system-clock gray_pixel/pixel_valid/frame_start signals. This core owns
// TWO raw 4-bit framebuffers, FAST/NMS, selection, orientation and descriptors.
// frame_start accompanies pixel (0,0). A busy core drops whole input frames;
// it never overwrites a frame still in use or mixes feature/frame identities.
// frame_ready is informational; the camera need not support backpressure.
module orb_accelerator #(
    parameter FRAME_WIDTH=640, FRAME_HEIGHT=480,
    parameter GRID_COLS=8, GRID_ROWS=6, TOP_N=8, EXTERNAL_FAST=0
)(
    input wire clk, reset,
    input wire [7:0] pixel_in,
    input wire pixel_valid, frame_start,
    input wire [7:0] fast_threshold,
    input wire external_kp_valid, external_fast_done,
    input wire [9:0] external_kp_x,
    input wire [8:0] external_kp_y,
    input wire [7:0] external_kp_score,
    output wire frame_ready,
    output reg frame_dropped,
    output reg [31:0] dropped_frames,
    output reg [31:0] aborted_frames,
    output wire descriptor_valid,
    input wire descriptor_ready,
    output wire [255:0] descriptor,
    output wire [4:0] angle_bin,
    output wire [9:0] feature_x,
    output wire [8:0] feature_y,
    output wire [7:0] feature_score,
    output reg [31:0] feature_frame_id,
    output reg [63:0] feature_timestamp,
    output wire frame_done,
    output reg [15:0] frame_feature_count,
    output reg completed_frame_valid,
    output reg completed_frame_bank
);
    localparam IDLE=0, CAPTURE=1, DRAIN=2, PROCESS=3;
    reg [1:0] state;
    reg capture_bank;
    reg raw_finished, fast_finished;
    reg [31:0] input_frame_id;
    reg [63:0] clock_ticks;
    reg [7:0] threshold_q;
    assign frame_ready = state == IDLE;
    wire accept_frame = frame_start && pixel_valid && frame_ready;
    wire accept_pixel = pixel_valid && (accept_frame ||
                       (state == CAPTURE && !frame_start));
    wire [3:0] raw_pixel;
    wire [9:0] write_x;
    wire [8:0] write_y;
    wire write_en, raw_done;
    // A new frame marker before all pixels arrive invalidates the partial
    // capture. Flush its tags and resume at the NEXT marker (drop this frame).
    wire abort_capture = frame_start && pixel_valid && state == CAPTURE && !raw_done;
    wire pipeline_reset = reset || abort_capture;
    test_pipeline #(.FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT)) raster (
        .clk(clk), .reset(pipeline_reset), .pixel_in(pixel_in), .pixel_valid(accept_pixel),
        .frame_start(accept_frame), .pixel_out(raw_pixel), .x(write_x), .y(write_y),
        .write_en(write_en), .frame_done(raw_done));
    wire kp_valid, fast_done;
    wire [9:0] kp_x;
    wire [8:0] kp_y;
    wire [7:0] kp_score;
    generate if (EXTERNAL_FAST) begin: shared_fast
        assign kp_valid = external_kp_valid && (state == CAPTURE || state == DRAIN);
        assign kp_x = external_kp_x;
        assign kp_y = external_kp_y;
        assign kp_score = external_kp_score;
        assign fast_done = external_fast_done;
    end else begin: own_fast
    fast_pipeline_top #(.FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT)) fast (
        .clk(clk), .reset(pipeline_reset), .pixel_in(pixel_in), .pixel_valid(accept_pixel),
        .frame_start(accept_frame), .threshold(accept_frame ? fast_threshold : threshold_q),
        .pixel_out(), .keypoint_out(), .x(), .y(), .write_en(),
        .frame_done(fast_done), .kp_valid(kp_valid), .kp_x(kp_x), .kp_y(kp_y),
        .kp_score(kp_score), .frame_keypoints(), .frame_keypoints_bcd());
    end endgenerate
    wire [9:0] fb_x;
    wire [8:0] fb_y;
    wire fb_en;
    wire [3:0] fb_data [0:1];
    wire [1:0] fb_ready, fb_valid;
    genvar bank;
    generate for (bank=0; bank<2; bank=bank+1) begin: frames
        frame_buffer #(.FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT),
            .DATA_WIDTH(4)) buffer_inst (
            .write_clk(clk), .reset(reset), .write_x(write_x), .write_y(write_y),
            .data_in(raw_pixel), .write_en(write_en && capture_bank == bank),
            .sys_read_x(fb_x), .sys_read_y(fb_y),
            .sys_read_en(fb_en && capture_bank == bank),
            .sys_data_out(fb_data[bank]), .sys_read_valid(fb_valid[bank]),
            .sys_read_ready(fb_ready[bank]), .read_clk(clk),
            .read_x(10'd0), .read_y(9'd0), .read_en(1'b0), .data_out());
    end endgenerate
    reg process_start;
    // Isolate camera FIFO -> frame/abort decode from the high-fanout frontend
    // reset and frame-start networks. Pipeline all feature-side events together.
    reg frontend_reset_q, frontend_start_q, frontend_done_q, frontend_kp_valid_q;
    reg [9:0] frontend_kp_x_q;
    reg [8:0] frontend_kp_y_q;
    reg [7:0] frontend_kp_score_q;
    always @(posedge clk) begin
        frontend_reset_q <= pipeline_reset;
        if (pipeline_reset) begin
            frontend_start_q <= 0; frontend_done_q <= 0; frontend_kp_valid_q <= 0;
            frontend_kp_x_q <= 0; frontend_kp_y_q <= 0; frontend_kp_score_q <= 0;
        end else begin
            frontend_start_q <= accept_frame;
            frontend_done_q <= process_start;
            frontend_kp_valid_q <= kp_valid;
            frontend_kp_x_q <= kp_x; frontend_kp_y_q <= kp_y;
            frontend_kp_score_q <= kp_score;
        end
    end
    orb_frontend #(.FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT),
        .GRID_COLS(GRID_COLS), .GRID_ROWS(GRID_ROWS), .TOP_N(TOP_N)) frontend (
        .clk(clk), .reset(frontend_reset_q), .frame_start(frontend_start_q),
        .frame_pixels_done(frontend_done_q), .kp_valid(frontend_kp_valid_q),
        .kp_x(frontend_kp_x_q), .kp_y(frontend_kp_y_q), .kp_score(frontend_kp_score_q),
        .fb_read_x(fb_x), .fb_read_y(fb_y), .fb_read_en(fb_en),
        .fb_read_ready(fb_ready[capture_bank]), .fb_read_valid(fb_valid[capture_bank]),
        .fb_read_data(fb_data[capture_bank]), .descriptor_valid(descriptor_valid),
        .descriptor_ready(descriptor_ready), .descriptor(descriptor), .angle_bin(angle_bin),
        .feature_x(feature_x), .feature_y(feature_y), .feature_score(feature_score),
        .frame_done(frame_done), .busy());
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE; capture_bank <= 0; raw_finished <= 0; fast_finished <= 0;
            input_frame_id <= 0; clock_ticks <= 0; threshold_q <= 0;
            feature_frame_id <= 0; feature_timestamp <= 0;
            frame_dropped <= 0; dropped_frames <= 0; aborted_frames <= 0; process_start <= 0;
            frame_feature_count <= 0; completed_frame_valid <= 0; completed_frame_bank <= 0;
        end else begin
            clock_ticks <= clock_ticks + 1'b1;
            process_start <= 0; frame_dropped <= 0;
            if (frame_start && pixel_valid) begin
                input_frame_id <= input_frame_id + 1'b1;
                if (!frame_ready) begin
                    frame_dropped <= 1; dropped_frames <= dropped_frames + 1'b1;
                end
            end
            if (accept_frame) begin
                state <= CAPTURE; raw_finished <= 0; fast_finished <= 0;
                feature_frame_id <= input_frame_id; feature_timestamp <= clock_ticks;
                threshold_q <= fast_threshold; frame_feature_count <= 0;
            end
            if (raw_done) begin raw_finished <= 1; state <= DRAIN; end
            if (fast_done && !accept_frame && (raw_finished || raw_done)) fast_finished <= 1;
            if (state == DRAIN && raw_finished && fast_finished) begin
                process_start <= 1; state <= PROCESS;
                completed_frame_valid <= 1; completed_frame_bank <= capture_bank;
            end
            if (descriptor_valid && descriptor_ready)
                frame_feature_count <= frame_feature_count + 1'b1;
            if (frame_done) begin capture_bank <= ~capture_bank; state <= IDLE; end
            if (abort_capture) begin
                state <= IDLE; raw_finished <= 0; fast_finished <= 0;
                process_start <= 0; frame_feature_count <= 0;
                aborted_frames <= aborted_frames + 1'b1;
            end
        end
    end
endmodule
