`timescale 1ns / 1ps

// Reads one square grayscale patch around a selected keypoint. Only one BRAM
// request is outstanding, keeping framebuffer latency and arbitration explicit.
module orb_patch_reader #(
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer PATCH_SIZE = 31,
    parameter integer PIXEL_WIDTH = 4
) (
    input  wire                   clk,
    input  wire                   reset,
    input  wire                   start,
    input  wire [9:0]             keypoint_x,
    input  wire [8:0]             keypoint_y,
    output wire                   start_ready,
    output wire                   busy,
    output reg  [9:0]             fb_read_x,
    output reg  [8:0]             fb_read_y,
    output wire                   fb_read_en,
    input  wire                   fb_read_ready,
    input  wire [PIXEL_WIDTH-1:0] fb_read_data,
    input  wire                   fb_read_valid,
    output reg                    patch_valid,
    output reg  [PIXEL_WIDTH-1:0] patch_pixel,
    output reg  [5:0]             patch_col,
    output reg  [5:0]             patch_row,
    output reg                    patch_done,
    output reg                    keypoint_rejected
);
    localparam integer RADIUS = PATCH_SIZE / 2;
    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] REQUEST = 2'd1;
    localparam [1:0] WAIT_DATA = 2'd2;

    reg [1:0] state;
    reg [9:0] center_x;
    reg [8:0] center_y;
    reg [5:0] request_col;
    reg [5:0] request_row;

    assign start_ready = (state == IDLE);
    assign busy = (state != IDLE);
    assign fb_read_en = (state == REQUEST) && fb_read_ready;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            center_x <= 0;
            center_y <= 0;
            fb_read_x <= 0; fb_read_y <= 0;
            request_col <= 0;
            request_row <= 0;
            patch_valid <= 1'b0;
            patch_pixel <= 0;
            patch_col <= 0;
            patch_row <= 0;
            patch_done <= 1'b0;
            keypoint_rejected <= 1'b0;
        end else begin
            patch_valid <= 1'b0;
            patch_done <= 1'b0;
            keypoint_rejected <= 1'b0;
            case (state)
                IDLE: begin
                    if (start) begin
                        if ((keypoint_x < RADIUS) ||
                            (keypoint_x >= FRAME_WIDTH - RADIUS) ||
                            (keypoint_y < RADIUS) ||
                            (keypoint_y >= FRAME_HEIGHT - RADIUS)) begin
                            keypoint_rejected <= 1'b1;
                            patch_done <= 1'b1;
                        end else begin
                            center_x <= keypoint_x;
                            center_y <= keypoint_y;
                            fb_read_x <= keypoint_x - RADIUS;
                            fb_read_y <= keypoint_y - RADIUS;
                            request_col <= 0;
                            request_row <= 0;
                            state <= REQUEST;
                        end
                    end
                end
                REQUEST: begin
                    if (fb_read_ready)
                        state <= WAIT_DATA;
                end
                WAIT_DATA: begin
                    if (fb_read_valid) begin
                        patch_valid <= 1'b1;
                        patch_pixel <= fb_read_data;
                        patch_col <= request_col;
                        patch_row <= request_row;
                        if ((request_col == PATCH_SIZE - 1) &&
                            (request_row == PATCH_SIZE - 1)) begin
                            patch_done <= 1'b1;
                            state <= IDLE;
                        end else begin
                            if (request_col == PATCH_SIZE - 1) begin
                                request_col <= 0;
                                request_row <= request_row + 1'b1;
                                fb_read_x <= center_x - RADIUS;
                                fb_read_y <= fb_read_y + 1'b1;
                            end else begin
                                request_col <= request_col + 1'b1;
                                fb_read_x <= fb_read_x + 1'b1;
                            end
                            state <= REQUEST;
                        end
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
