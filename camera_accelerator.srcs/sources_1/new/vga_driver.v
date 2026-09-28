`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/23/2026 02:54:45 PM
// Design Name: 
// Module Name: vga_driver
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module vga_driver(
         vga_clk, reset, pixel_in,
         Red, Green, Blue, hsync, vsync,
         rd_addr_x, rd_addr_y, read_en
    );
    
    // IN n OUTs
    input vga_clk, reset;
    input [3:0] pixel_in;
    
    output [3:0] Red, Green, Blue;
    output hsync, vsync;
    
    output [9:0] rd_addr_x;
    output [8:0] rd_addr_y; 
    output read_en;
    
    // INTERNAL wires and regs
    reg [9:0] h_counter;
    reg [9:0] v_counter;
    
    wire active_video_cur;
    wire hsync_cur;
    wire vsync_cur;
    
    reg active_video_delayed;
    reg hsync_delayed;
    reg vsync_delayed;
    
    wire [3:0] pixel_int;
    
    parameter white = 255;
    parameter black = 0;
   
    // HSYNC & VSYNC Driver based on counter values
    assign hsync_cur = !((h_counter > 655) & (h_counter < 752)); // active low [656:751]
    
    assign vsync_cur = !((v_counter > 489) & (v_counter < 492)); // active low [490:491]
    
    assign active_video_cur = (h_counter < 640) & (v_counter < 480);
    
    // addressing
    assign rd_addr_x = active_video_cur ? h_counter : 0;
    assign rd_addr_y = active_video_cur ? v_counter[8:0] : 0;
    
    assign read_en = active_video_cur;


    // VGA Scan counter: 800 x 525 total
    always @(posedge vga_clk, posedge reset)
    begin: VGA_COUNTERS
        if (reset) begin
            h_counter <= 0;
            v_counter <= 0;
        end
        else if (h_counter == 799) begin
            h_counter <= 0;
            
            if (v_counter == 524) begin
                v_counter <= 0;
            end
            else 
                v_counter <= v_counter + 1;
        end
        else
            h_counter <= h_counter + 1;
    end
    
    
    // delaying data 1 clock because of frame buffer read delay
    always @(posedge vga_clk)
    begin: DATA_DELAY
        if (reset) begin
            active_video_delayed <= 0;
            hsync_delayed <= 1;
            vsync_delayed <= 1;
        end
        else begin
            active_video_delayed <= active_video_cur;
            hsync_delayed <= hsync_cur;
            vsync_delayed <= vsync_cur;
        end
    end
    
    
    // Final assignments 
    assign Red = active_video_delayed ? pixel_int : 0;
    assign Green = active_video_delayed ? pixel_int : 0;
    assign Blue = active_video_delayed ? pixel_int : 0;
    
    assign pixel_int = active_video_delayed ? pixel_in : 0;
    
    assign hsync = hsync_delayed;
    assign vsync = vsync_delayed;
    
    
endmodule
