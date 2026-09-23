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
         clk, reset, Red, Green, Blue, hsync, vsync
    );
    
    // IN n OUTs
    //input [7:0] pixel_in; // TODO: Add back in
    input clk, reset;
    
    output [7:0] Red, Green, Blue;
    output hsync, vsync;
    
    // INTERNAL wires and regs
    reg [3:0] div_clk;
    wire vga_clk;
    wire active_video;
    reg [9:0] h_counter;
    reg [9:0] v_counter;
    wire [7:0] pixel_int; // check if only 4 bits?
    parameter white = 255;
    parameter black = 0;
    
    // VGA CLOCK GEN
    always @(posedge clk, posedge reset) 
    begin: CLK_DIV 
        if (reset) 
            div_clk <= 0;
        else 
            div_clk <= div_clk + 1'b1;
    end
    
    assign vga_clk = div_clk[1]; // 100 MHz / 2^2 = 25 MHz
    
    
    // HSYNC & VSYNC Driver based on counter values
    // TODO: make pixel pattern better
    assign hsync = !((h_counter > 655) & (h_counter < 752)); // active low [656:751]
    assign vsync = !((v_counter > 489) & (v_counter < 492)); // active low [490:491]
    
    assign active_video = (h_counter < 640) & (v_counter < 480);
    assign pixel_int = (active_video) ? white : black;
    
    assign Red = pixel_int;
    assign Green = pixel_int;
    assign Blue = pixel_int;
    
    
    // Horizontal and Vertical Countera
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
    
endmodule
