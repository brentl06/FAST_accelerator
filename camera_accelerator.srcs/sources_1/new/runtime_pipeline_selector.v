`timescale 1ns / 1ps

// Runs the raw and Sobel pipelines in parallel and selects one complete frame
// at a time. mode_select is synchronized here because it comes from a board
// switch rather than the system clock domain.
module runtime_pipeline_selector #(
    parameter FRAME_WIDTH = 640,
    parameter FRAME_HEIGHT = 480
)(
    input  wire [7:0] pixel_in,
    input  wire       pixel_valid,
    input  wire       frame_start,
    input  wire       mode_select,
    input  wire [3:0] threshold_select,
    input  wire       clk,
    input  wire       reset,

    output wire [3:0] pixel_out,
    output wire [9:0] x,
    output wire [8:0] y,
    output wire       write_en,
    output wire       frame_done,
    output reg        active_mode,
    output reg        mode_changed,
    output reg [10:0] active_threshold
);

    // SW1 = 0 selects raw grayscale; SW1 = 1 selects Sobel edges.
    (* ASYNC_REG = "TRUE" *) reg [1:0] mode_select_sync;
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

    function [10:0] threshold_from_switches;
        input [3:0] switch_value;
        begin
            threshold_from_switches = switch_value * 11'd25;
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            mode_select_sync <= 2'b00;
            threshold_select_meta <= 4'b0000;
            threshold_select_sync <= 4'b0000;
        end else begin
            mode_select_sync <= {mode_select_sync[0], mode_select};
            threshold_select_meta <= threshold_select;
            threshold_select_sync <= threshold_select_meta;
        end
    end

    // A physical switch may move at any time, but the framebuffer source must
    // not change partway through a frame. Capture the requested mode only when
    // the camera marks the first pixel of a new frame.
    always @(posedge clk) begin
        if (reset) begin
            active_mode <= 1'b0;
            mode_changed <= 1'b0;
            active_threshold <= 11'd0;
        end else begin
            mode_changed <= 1'b0;

            if (frame_start)
                active_threshold <= threshold_from_switches(threshold_select_sync);

            if (frame_start && (active_mode != mode_select_sync[1])) begin
                active_mode <= mode_select_sync[1];
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

    // Only the selected branch reaches the framebuffer write port. Both
    // branches continue running so either is aligned and ready next frame.
    assign pixel_out = active_mode ? edge_pixel_out : raw_pixel_out;
    assign x = active_mode ? edge_x : raw_x;
    assign y = active_mode ? edge_y : raw_y;
    assign write_en = active_mode ? edge_write_en : raw_write_en;
    assign frame_done = active_mode ? edge_frame_done : raw_frame_done;

endmodule
