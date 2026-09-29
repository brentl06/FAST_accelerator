`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/28/2026 04:29:54 PM
// Design Name: 
// Module Name: test_pipeline
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


module test_pipeline#(
    parameter FRAME_WIDTH = 640,
    parameter FRAME_HEIGHT = 480
    )(
    input [7:0] pixel_in,
    input pixel_valid,
    input frame_start,
    input clk, reset,
    
    output reg [3:0] pixel_out,
    output reg [9:0] x,
    output reg [8:0] y,
    output reg write_en
    );
    
    // Internal Regs and Wires
    reg [9:0] x_int;
    reg [8:0] y_int;
    
    always @(posedge clk)
    begin: PIXEL_AND_COORDINATE_PIPELINE
        if (reset) begin
            pixel_out <= 0;
            x <= 0;
            y <= 0;
            write_en <= 0;
            x_int <= 0;
            y_int <= 0;
        end else begin
            write_en <= pixel_valid;

            if (pixel_valid) begin
                pixel_out <= pixel_in[7:4];

                // frame_start accompanies the first valid pixel of a frame.
                // Write that pixel at (0,0), then prepare (1,0).
                if (frame_start) begin
                    x <= 0;
                    y <= 0;
                    x_int <= (FRAME_WIDTH > 1) ? 1 : 0;
                    y_int <= 0;
                end else begin
                    x <= x_int;
                    y <= y_int;

                    if (x_int == FRAME_WIDTH - 1) begin
                        x_int <= 0;
                        if (y_int == FRAME_HEIGHT - 1)
                            y_int <= 0;
                        else
                            y_int <= y_int + 1'b1;
                    end else begin
                        x_int <= x_int + 1'b1;
                    end
                end
            end
        end
    end
    
endmodule
