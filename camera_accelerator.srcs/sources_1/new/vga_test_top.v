`timescale 1ns / 1ps

// Minimal OV7670-to-VGA pipeline for the Nexys A7.
// The OV7670 must output 640x480 YUV422. SW0 selects which byte pair is stored.
// SW1 selects raw grayscale (0) or Sobel edges (1) at the next frame boundary.
// SW2 selects the FAST keypoint overlay (overrides SW1).
// SW15:SW12 select the Sobel threshold in increments of 25, or in FAST mode
// the FAST threshold 5..80 in increments of 5.
module vga_test_top (
    // Internal to FPGA Dev Board
    input  wire       CLK100MHZ,
    input  wire       CPU_RESETN,
    input  wire       SW0,
    input  wire       SW1,
    input  wire       SW2,
    input  wire       SW12,
    input  wire       SW13,
    input  wire       SW14,
    input  wire       SW15,

    // Inputs/Outputs from Camera Module
    input  wire       CAM_PCLK,
    input  wire       CAM_HREF,
    input  wire       CAM_VSYNC,
    input  wire [7:0] CAM_DATA,
    output wire       CAM_XCLK,
    output wire       CAM_RESET,

    // Outputs to Display
    output wire [3:0] VGA_R,
    output wire [3:0] VGA_G,
    output wire [3:0] VGA_B,
    output wire       VGA_HS,
    output wire       VGA_VS,

    // Seven-segment status display
    output wire       CA,
    output wire       CB,
    output wire       CC,
    output wire       CD,
    output wire       CE,
    output wire       CF,
    output wire       CG,
    output wire       DP,
    output wire [7:0] AN
);

    wire reset;
    assign reset = !CPU_RESETN;
    assign CAM_RESET = CPU_RESETN; // OV7670 RESET is active low.

    // Divide the 100 MHz board clock by four for VGA and camera XCLK.
    reg [1:0] pixel_clock_divider;
    wire vga_clk_unbuffered;
    wire vga_clk;

    assign vga_clk_unbuffered = pixel_clock_divider[1];

    always @(posedge CLK100MHZ or posedge reset) begin
        if (reset)
            pixel_clock_divider <= 0;
        else
            pixel_clock_divider <= pixel_clock_divider + 1'b1;
    end

    BUFG vga_clock_buffer (
        .I(vga_clk_unbuffered),
        .O(vga_clk)
    );

    // Forward the 25 MHz clock through an output register for a clean XCLK.
    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE")
    ) camera_xclk_output (
        .Q(CAM_XCLK),
        .C(vga_clk),
        .CE(1'b1),
        .D1(1'b1),
        .D2(1'b0),
        .R(reset),
        .S(1'b0)
    );

    // Camera capture crosses CAM_PCLK into CLK100MHZ through its async FIFO.
    wire [7:0] camera_gray_pixel;
    wire camera_pixel_valid;
    wire camera_frame_start;

    OV7670_interface camera_capture (
        .pclk(CAM_PCLK),
        .sysclk(CLK100MHZ),
        .href(CAM_HREF),
        .vsync(CAM_VSYNC),
        .rst(reset),
        .data(CAM_DATA),
        .byte_select(SW0),
        .gray_pixel(camera_gray_pixel),
        .pixel_valid(camera_pixel_valid),
        .frame_start(camera_frame_start)
    );

    // Convert the valid pixel stream into framebuffer writes.
    wire [3:0] write_data;
    wire [9:0] write_x;
    wire [8:0] write_y;
    wire write_en;
    wire frame_done;
    wire [1:0] processing_mode;
    wire mode_changed;
    wire [10:0] active_threshold;
    wire [15:0] frame_keypoints_bcd;

    runtime_pipeline_selector camera_write_pipeline (
        .pixel_in(camera_gray_pixel),
        .pixel_valid(camera_pixel_valid),
        .frame_start(camera_frame_start),
        .mode_select(SW1),
        .fast_select(SW2),
        .threshold_select({SW15, SW14, SW13, SW12}),
        .clk(CLK100MHZ),
        .reset(reset),
        .pixel_out(write_data),
        .x(write_x),
        .y(write_y),
        .write_en(write_en),
        .frame_done(frame_done),
        .active_mode(processing_mode),
        .mode_changed(mode_changed),
        .active_threshold(active_threshold),
        .kp_valid(),
        .kp_x(),
        .kp_y(),
        .kp_score(),
        .frame_keypoints(),
        .frame_keypoints_bcd(frame_keypoints_bcd)
    );

    wire [6:0] status_segments;

    seven_segment_status status_display (
        .clk(CLK100MHZ),
        .reset(reset),
        .processing_mode(processing_mode != 2'd0),
        .threshold(active_threshold),
        .show_count(processing_mode == 2'd2),
        .count_bcd(frame_keypoints_bcd),
        .segments(status_segments),
        .decimal_point(DP),
        .anodes(AN)
    );

    assign {CA, CB, CC, CD, CE, CF, CG} = status_segments;

    // Keep VGA blanked until one complete frame from the selected mode has
    // been stored. The framebuffer pipelines writes by one system clock, so
    // delay frame_done by the same amount before declaring the frame complete.
    // A mode change invalidates the frame currently on display.
    reg first_frame_complete;
    reg frame_done_delayed;
    always @(posedge CLK100MHZ or posedge reset) begin
        if (reset) begin
            first_frame_complete <= 0;
            frame_done_delayed    <= 0;
        end else begin
            frame_done_delayed <= frame_done;

            if (mode_changed)
                first_frame_complete <= 0;
            else if (frame_done_delayed)
                first_frame_complete <= 1;
        end
    end

    (* ASYNC_REG = "TRUE" *) reg [1:0] frame_complete_sync;
    wire vga_reset;

    // Delays first_frame_complete
    always @(posedge vga_clk or posedge reset) begin
        if (reset)
            frame_complete_sync <= 0;
        else
            frame_complete_sync <= {frame_complete_sync[0], first_frame_complete};
    end

    assign vga_reset = reset || !frame_complete_sync[1];

    wire [9:0] read_x;
    wire [8:0] read_y;
    wire read_en;
    wire [3:0] framebuffer_pixel;
    wire [3:0] display_pixel;
    // Two 2-bit synchronizer stages. The mode only changes at a frame boundary
    // while the display is blanked (vga_reset), so a briefly mixed value is
    // never visible.
    (* ASYNC_REG = "TRUE" *) reg [1:0] processing_mode_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] processing_mode_sync;
    reg        processed_border_delayed;

    frame_buffer framebuffer (
        .write_clk(CLK100MHZ),
        .write_x(write_x),
        .write_y(write_y),
        .data_in(write_data),
        .write_en(write_en),
        .read_clk(vga_clk),
        .read_x(read_x),
        .read_y(read_y),
        .read_en(read_en),
        .data_out(framebuffer_pixel),
        .reset(reset)
    );

    // Synchronize the selected mode into the VGA clock domain. The border
    // decision is registered to match the framebuffer's one-clock read delay.
    // This prevents stale raw pixels from appearing around a processed frame:
    // Sobel never writes the 1-pixel border, FAST never writes the last 4
    // columns and rows.
    always @(posedge vga_clk or posedge reset) begin
        if (reset) begin
            processing_mode_meta <= 2'b00;
            processing_mode_sync <= 2'b00;
            processed_border_delayed <= 1'b0;
        end else begin
            processing_mode_meta <= processing_mode;
            processing_mode_sync <= processing_mode_meta;
            processed_border_delayed <= read_en && (
                ((processing_mode_sync == 2'd1) &&
                 ((read_x == 0) || (read_x == 639) ||
                  (read_y == 0) || (read_y == 479))) ||
                ((processing_mode_sync == 2'd2) &&
                 ((read_x >= 636) || (read_y >= 476))));
        end
    end

    assign display_pixel = processed_border_delayed ? 4'h0 : framebuffer_pixel;

    vga_driver driver (
        .vga_clk(vga_clk),
        .reset(vga_reset),
        .pixel_in(display_pixel),
        .Red(VGA_R),
        .Green(VGA_G),
        .Blue(VGA_B),
        .hsync(VGA_HS),
        .vsync(VGA_VS),
        .rd_addr_x(read_x),
        .rd_addr_y(read_y),
        .read_en(read_en)
    );

endmodule
