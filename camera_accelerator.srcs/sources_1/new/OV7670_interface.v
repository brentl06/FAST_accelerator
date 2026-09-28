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


// TO IMPLEMENT:
// STATE MACHINE WITH SETUP + ACTIVE STATES 
// SETUP : CONFIGURING CAM ON STARTUP (multiple states likely)
// ACTIVE : CURRENT LOGIC

module OV7670_interface(
    pclk, sysclk, href, vsync, rst, data, 
    gray_pixel, pixel_valid, frame_start
    );
    
    // IN n OUT
    input pclk, sysclk, href, vsync, rst;
    input [7:0] data;
    
    output [7:0] gray_pixel;
    output pixel_valid;
    output frame_start;
    
    // Internal Wires and Reg
    wire fifo_wr_en;
    wire fifo_rd_en;
    wire fifo_valid;
    wire fifo_empty;
    wire rd_rst_busy;
    wire wr_rst_busy;
    wire [8:0] fifo_data_in;
    wire [8:0] fifo_data_out;
    reg frame_start_pending;

    reg [1:0] byte_counter;
    
    // FIFO declaration
    fifo_generator_0 CAM_FIFO (
        .wr_clk(pclk), .rd_clk(sysclk), .rst(rst), .din(fifo_data_in), 
        .wr_en(fifo_wr_en), .rd_en(fifo_rd_en),
        .dout(fifo_data_out), .full(full), .empty(fifo_empty),
        .wr_rst_busy(wr_rst_busy), .rd_rst_busy(rd_rst_busy), .valid(fifo_valid)
    );

    // FIFO Inputs (YUV422) 
    assign fifo_data_in = {frame_start_pending, data};
    assign fifo_wr_en = (href & !rst & !vsync 
    & !wr_rst_busy &((byte_counter==2) | (byte_counter==0)));
    
    // FIFO Outputs -> Module Outputs
    assign gray_pixel = fifo_data_out[7:0];
    assign frame_start = fifo_data_out[8] & pixel_valid;
    assign pixel_valid =  fifo_valid & !rd_rst_busy & !rst;
    
    // Internal FIFO rd_en, continue incrementing through data if available
    assign fifo_rd_en  =  !fifo_empty & !rd_rst_busy & !rst;
   
    
    always @(posedge pclk) 
    begin: BYTE_COUNTER 
        if ((rst | vsync) & !href)
            byte_counter <= 0;     
        else // if (href)
            byte_counter <= byte_counter + 1;
    end
    
    always @(posedge pclk) 
    begin: FRAME_START_LOGIC
        if (rst)
            frame_start_pending <= 0;
        else if (vsync)
            frame_start_pending <= 1;
        else if (fifo_wr_en)
            frame_start_pending <= 0;
    end
    
endmodule
