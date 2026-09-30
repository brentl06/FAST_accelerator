`timescale 1ns / 1ps

// Streaming camera-processing pipeline with framebuffer-ready outputs.
// A complete 3x3 neighborhood exists only for image centers (1,1) through
// (FRAME_WIDTH-2, FRAME_HEIGHT-2), so the one-pixel border is not written.
module processing_pipeline_top #(
    parameter FRAME_WIDTH = 640,
    parameter FRAME_HEIGHT = 480
)(
    input  wire [7:0] pixel_in,
    input  wire       pixel_valid,
    input  wire       frame_start,
    input  wire [10:0] edge_threshold,
    input  wire       clk,
    input  wire       reset,

    output reg  [3:0] pixel_out,
    output reg  [9:0] x,
    output reg  [8:0] y,
    output reg        write_en,
    output reg        frame_done
);

    localparam [9:0] LAST_X = FRAME_WIDTH - 2;
    localparam [8:0] LAST_Y = FRAME_HEIGHT - 2;

    wire [7:0] w00, w01, w02;
    wire [7:0] w10, w11, w12;
    wire [7:0] w20, w21, w22;
    wire       window_valid;
    wire       sobel_valid;
    wire       edge_detected;

    reg [9:0] next_x;
    reg [8:0] next_y;
    reg       frame_armed;

    sliding_window #(
        .IMAGE_WIDTH(FRAME_WIDTH),
        .IMAGE_HEIGHT(FRAME_HEIGHT)
    ) window_3x3 (
        .clk(clk),
        .reset(reset),
        .pixel(pixel_in),
        .pixel_valid(pixel_valid),
        .w00(w00), .w01(w01), .w02(w02),
        .w10(w10), .w11(w11), .w12(w12),
        .w20(w20), .w21(w21), .w22(w22),
        .window_valid(window_valid)
    );

    sobel_filter filter (
        .clk(clk),
        .reset(reset),
        .window_valid(window_valid),
        .edge_threshold(edge_threshold),
        .w00(w00), .w01(w01), .w02(w02),
        .w10(w10), .w11(w11), .w12(w12),
        .w20(w20), .w21(w21), .w22(w22),
        .out_valid(sobel_valid),
        .edge_detected(edge_detected)
    );

    // Coordinates are generated at the final Sobel stage. This relies on the
    // window/filter chain emitting exactly FRAME_WIDTH-2 ordered values per
    // processed row.
    always @(posedge clk) begin
        if (reset) begin
            pixel_out  <= 4'h0;
            x          <= 10'd0;
            y          <= 9'd0;
            write_en   <= 1'b0;
            frame_done <= 1'b0;
            next_x     <= 10'd1;
            next_y     <= 9'd1;
            frame_armed <= 1'b0;
        end else begin
            write_en   <= 1'b0;
            frame_done <= 1'b0;

            // frame_start accompanies the first input pixel. Re-arm the output
            // coordinates before the first Sobel result reaches this stage.
            if (frame_start) begin
                next_x      <= 10'd1;
                next_y      <= 9'd1;
                frame_armed <= 1'b1;
            end else if (sobel_valid && frame_armed) begin
                pixel_out <= edge_detected ? 4'hF : 4'h0;
                x         <= next_x;
                y         <= next_y;
                write_en  <= 1'b1;

                if ((next_x == LAST_X) && (next_y == LAST_Y)) begin
                    frame_done  <= 1;
                    frame_armed <= 0;
                    next_x      <= 1;
                    next_y      <= 1;
                end else if (next_x == LAST_X) begin
                    next_x <= 1;
                    next_y <= next_y + 1;
                end else begin
                    next_x <= next_x + 1'b1;
                end
            end
        end
    end

endmodule
