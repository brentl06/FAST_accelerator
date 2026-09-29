`timescale 1ns / 1ps

// Minimal OV7670-to-VGA pipeline for the Nexys A7.
// The OV7670 must output 640x480 YUV422. SW0 selects which byte pair is stored:
// 0 = bytes 2/4; 1 = bytes 1/3.
module vga_test_top (
    input  wire       CLK100MHZ,
    input  wire       CPU_RESETN,
    input  wire       SW0,

    input  wire       CAM_PCLK,
    input  wire       CAM_HREF,
    input  wire       CAM_VSYNC,
    input  wire [7:0] CAM_DATA,
    output wire       CAM_XCLK,
    output wire       CAM_RESET,

    output wire [3:0] VGA_R,
    output wire [3:0] VGA_G,
    output wire [3:0] VGA_B,
    output wire       VGA_HS,
    output wire       VGA_VS
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

    test_pipeline camera_write_pipeline (
        .pixel_in(camera_gray_pixel),
        .pixel_valid(camera_pixel_valid),
        .frame_start(camera_frame_start),
        .clk(CLK100MHZ),
        .reset(reset),
        .pixel_out(write_data),
        .x(write_x),
        .y(write_y),
        .write_en(write_en)
    );

    // Do not scan uninitialized framebuffer memory. The last registered write
    // of the first frame makes the display eligible to start.
    reg first_frame_complete;
    always @(posedge CLK100MHZ or posedge reset) begin
        if (reset)
            first_frame_complete <= 0;
        else if (write_en && (write_x == 639) && (write_y == 479))
            first_frame_complete <= 1;
    end

    reg [1:0] frame_complete_sync;
    wire vga_reset;

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
    wire [3:0] pixel_data;

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
        .data_out(pixel_data),
        .reset(reset)
    );

    vga_driver driver (
        .vga_clk(vga_clk),
        .reset(vga_reset),
        .pixel_in(pixel_data),
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
