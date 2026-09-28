`timescale 1ns / 1ps

// Standalone Nexys A7 test for frame_buffer + vga_driver.
// PATTERN_SEL = 0: checkerboard
// PATTERN_SEL = 1: vertical grayscale bars
// Set PATTERN_SEL, then press CPU_RESETN to reload the selected pattern.
module vga_test_top (
    input  wire       CLK100MHZ,
    input  wire       CPU_RESETN,
    input  wire       PATTERN_SEL,
    output wire [3:0] VGA_R,
    output wire [3:0] VGA_G,
    output wire [3:0] VGA_B,
    output wire       VGA_HS,
    output wire       VGA_VS
);

    wire reset;
    assign reset = !CPU_RESETN;

    // Divide the board's 100 MHz clock by four and place it on a clock buffer.
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

    // Sequentially initialize all 640x480 framebuffer locations.
    reg [9:0] write_x;
    reg [8:0] write_y;
    reg write_en;
    reg init_done;
    wire checker_pixel;
    wire [3:0] write_data;

    assign checker_pixel = write_x[5] ^ write_y[5];
    assign write_data = PATTERN_SEL ? write_x[9:6] :
                        (checker_pixel ? 4'hf : 4'h0);

    always @(posedge CLK100MHZ or posedge reset) begin
        if (reset) begin
            write_x <= 0;
            write_y <= 0;
            write_en <= 1;
            init_done <= 0;
        end else if (write_en) begin
            if (write_x == 639) begin
                write_x <= 0;
                if (write_y == 479) begin
                    write_en <= 0;
                    init_done <= 1;
                end else begin
                    write_y <= write_y + 1'b1;
                end
            end else begin
                write_x <= write_x + 1'b1;
            end
        end
    end

    // Safely release the VGA domain after the framebuffer is initialized.
    reg [1:0] init_done_sync;
    wire vga_reset;

    always @(posedge vga_clk or posedge reset) begin
        if (reset)
            init_done_sync <= 0;
        else
            init_done_sync <= {init_done_sync[0], init_done};
    end

    assign vga_reset = reset || !init_done_sync[1];

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
