`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/19/2026 04:32:59 PM
// Design Name: 
// Module Name: sobel_filter
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


module sobel_filter #(
      parameter [10:0] EDGE_THRESHOLD = 11'd300
    )
    ( clk, reset, window_valid,
      w00, w01, w02, w10, w11, w12, w20, w21, w22,
      out_valid, edge_detected      
    );
    
    // IN and OUTS
    input    clk, reset;
    input    window_valid;
    
    input [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
    
    output reg out_valid;
    output reg edge_detected;
    
    // Internal Regs and Wires
    reg signed [10:0] gx, gy;
    wire [10:0] abs_gx, abs_gy;
    reg [10:0] magnitude;
    reg         g_valid;
    
    // sliding window values extended and unsigned -> signed
    wire signed [10:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    
    assign {p00,p01,p02} = {{3'b000,w00}, {3'b000,w01}, {3'b000,w02}};
    assign {p10,p11,p12} = {{3'b000,w10}, {3'b000,w11}, {3'b000,w12}};
    assign {p20,p21,p22} = {{3'b000,w20}, {3'b000,w21}, {3'b000,w22}};
    
    // if negative, flip sign to make positive, else keep pos
    assign abs_gx = gx[10] ? -gx : gx;
    assign abs_gy = gy[10] ? -gy : gy;
    
    // gx & gy calculations + edge thresholding
    always @(posedge clk)
    begin: GRADIENT_CALCULATIONS
        if (reset) begin
            gx <= 0;
            gy <= 0;
            g_valid <= 0;
        end
        else begin
            g_valid <= window_valid;
            
            if (window_valid) begin
                gx <= -p00 - (p10<<1) - p20 + p02 + (p12<<1) + p22;
                gy <= -p00 - (p01<<1) - p02 + p20 + (p21<<1) + p22;
            end
        end 
    end
    
    // registered magnitude and edge detection, can only run after valud gradient calcs
    always @(posedge clk) 
    begin: MAGNITUDE_EDGE_CALCULATIONS
        if (reset) begin
            magnitude <= 0;
            edge_detected <= 0;
            out_valid <= 0;
        end
        else begin
            out_valid <= g_valid;
            if (g_valid) begin
                magnitude <= abs_gx + abs_gy;
                edge_detected <= ((abs_gx + abs_gy) >= EDGE_THRESHOLD);
            end
            else edge_detected <= 0;
        end
    end
    
   
    
endmodule
