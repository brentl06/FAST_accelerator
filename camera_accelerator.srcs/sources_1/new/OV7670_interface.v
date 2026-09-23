`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/22/2026 04:49:02 PM
// Design Name: 
// Module Name: OV7670_interface
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


module OV7670_interface(
    pclk, sysclk, href, vsync, rst, data, gray_pixel,
    pixel_valid
    );
    
    // IN n OUT
    input pclk, sysclk, href, vsync, rst;
    input [7:0] data;
    
    output [7:0] gray_pixel;
    output pixel_valid;
    
    // Internal Wires and Reg
    wire fifo_wr_en;
    wire fifo_rd_en;
    wire fifo_valid;
    wire fifo_empty;
    wire rd_rst_busy;
    wire wr_rst_busy;

    reg [1:0] byte_counter;
    
    // FIFO declaration
    fifo_generator_0 CAM_FIFO (
        .wr_clk(pclk), .rd_clk(sysclk), .rst(rst), .din(data), 
        .wr_en(fifo_wr_en), .rd_en(fifo_rd_en),
        .dout(gray_pixel), .full(full), .empty(fifo_empty),
        .wr_rst_busy(wr_rst_busy), .rd_rst_busy(rd_rst_busy), .valid(fifo_valid)
    );

    // Letting other module know data ready, continue incrementing while not empty
    assign pixel_valid =  fifo_valid & !rd_rst_busy & !rst;
    assign fifo_rd_en  =  !fifo_empty & !rd_rst_busy & !rst;
    
    // YUV422 : Y0, U, Y1, V where Y is luminance 
    assign fifo_wr_en = (href & !rst & !vsync & !wr_rst_busy &
    ((byte_counter==2) | (byte_counter==0)));
   
    always @(posedge pclk) 
    begin: BYTE_COUNTER
        byte_counter <= 0;
        if (href & !(rst | vsync)) byte_counter <= byte_counter + 1;
    end
    
endmodule
