`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/18/2026 01:30:40 PM
// Design Name: 
// Module Name: sliding_window
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


module sliding_window#(
        parameter IMAGE_WIDTH = 640,
        parameter IMAGE_HEIGHT = 480
    )
    (
    // input module declaration with inputs and outputs
        clk, reset, pixel, pixel_valid, 
        w00, w01, w02, 
        w10, w11, w12, 
        w20, w21, w22, window_valid    
    );
    
    // IN & OUT
    input clk, reset;
    input [7:0] pixel;
    input       pixel_valid;
    
    output [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
    output reg window_valid;
    
    // Internal Wires & Regs
    
    // seperate the window into rows
    reg [9:0]  col = 0;
    reg [8:0]  row = 0;
    
    reg [7:0]  w_r0[0:2];
    reg [7:0]  w_r1[0:2]; 
    reg [7:0]  w_r2[0:2];
    // line buffers 640 x 8-bit wide pixels
    reg [7:0]    lb0 [0 : IMAGE_WIDTH - 1];
    reg [7:0]    lb1 [0 : IMAGE_WIDTH - 1];
    
    // driving pixels with row declarations
    assign {w00,w01,w02} = {w_r0[0], w_r0[1], w_r0[2]};
    assign {w10,w11,w12} = {w_r1[0], w_r1[1], w_r1[2]};
    assign {w20,w21,w22} = {w_r2[0], w_r2[1], w_r2[2]};
    
    always @ (posedge clk) 
    begin: COL_ROW_COUNTER
        if (reset) begin
            col <= 0;
            row <= 0;
        end
        else if (pixel_valid) begin
            
            if (col == IMAGE_WIDTH - 1) begin
                col <= 0;
                
                if (row == IMAGE_HEIGHT - 1) row <= 0;
                else row <= row + 1;
            end
            else begin
                col <= col + 1;
            end 
        end
    end
        
    always @ (posedge clk) 
    begin: SHIFTING_LOGIC
        if (reset) begin
            {w_r0[0], w_r0[1], w_r0[2]} <= {8'd0, 8'd0, 8'd0};
            {w_r1[0], w_r1[1], w_r1[2]} <= {8'd0, 8'd0, 8'd0};
            {w_r2[0], w_r2[1], w_r2[2]} <= {8'd0, 8'd0, 8'd0};
        end
        else if (pixel_valid) begin
        // Traversing through line buffer
            lb0[col] <= lb1[col];
            lb1[col] <= pixel;
            
        // Sliding Window Shifting
            {w_r0[0], w_r0[1], w_r0[2]} <= {w_r0[1], w_r0[2], lb0[col]};
            {w_r1[0], w_r1[1], w_r1[2]} <= {w_r1[1], w_r1[2], lb1[col]};
            {w_r2[0], w_r2[1], w_r2[2]} <= {w_r2[1], w_r2[2], pixel};
        end
        
        window_valid <= (row >= 2) & (col >= 2) & pixel_valid;
    end
    
endmodule
