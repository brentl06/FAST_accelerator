`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/23/2026 12:53:24 AM
// Design Name: 
// Module Name: top
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


module top(
        reset, clk, pclk, href, vsync, data_in,
        out_valid, edge_detected
    );
    // FPGA LEVEL IN | OUT
    input reset;
    input clk; // 100 Mhz clock
    
    //OV7670
    input pclk, href, vsync;
    input [7:0] data_in;
    
    output out_valid, edge_detected;    
    
    // INTERNAL
    wire pixel_valid;
    wire [7:0] pixel; 
    wire window_valid;
    wire [7:0] w00,w01,w02,w10,w11,w12,w20,w21,w22;
    
    // connect from external camera from pmod 
    // -> ov7670 -> sliding_window -> sobel_filter
    
    OV7670_interface camera_module(
        .pclk(pclk), .sysclk(clk), .href(href), .vsync(vsync),
        .rst(reset), .data(data_in), .gray_pixel(pixel), .pixel_valid(pixel_valid)
    );
    
    sliding_window #(.IMAGE_WIDTH(640), .IMAGE_HEIGHT(480))
    window_3x3(
        .clk(clk), .reset(reset), .pixel(pixel), .pixel_valid(pixel_valid),
        .w00(w00), .w01(w01), .w02(w02), 
        .w10(w10), .w11(w11), .w12(w12), 
        .w20(w20), .w21(w21), .w22(w22), .window_valid(window_valid)        
    );
    
    sobel_filter filter_module(
        .clk(clk), .reset(reset), .window_valid(window_valid),
        .w00(), .w01(), .w02(), .w10(), .w11(), .w12(), 
        .w20(), .w21(), .w22(),
        .out_valid(out_valid), .edge_detected(edge_detected)
    );
endmodule
