`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/24/2026 09:44:16 PM
// Design Name: 
// Module Name: frame_buffer
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

// FRAME BUFFER TO INTERFACE WITH PROCESSING PIPELINE AND VGA DRIVER

module frame_buffer#(
        parameter FRAME_WIDTH = 640,
        parameter FRAME_HEIGHT = 480
    )( 
        write_clk, write_x, write_y, data_in, write_en,
        read_clk, read_x, read_y, read_en,
        data_out, reset
    );
    input reset;
    
    // SYS write side
    input write_clk;
    input [9:0] write_x;
    input [8:0] write_y;
    input [3:0] data_in;
    input write_en;
    
    // VGA read side 
    input read_clk;
    input [9:0] read_x;
    input [8:0] read_y; 
    input read_en;
    
    output reg [3:0] data_out;
    
    // INTERNAL REGs and WIRES
    localparam FRAME_SIZE = FRAME_WIDTH * FRAME_HEIGHT;
    wire [18:0] rd_addr;
    wire [18:0] wr_addr;
    wire valid_rd_addr;
    wire valid_wr_addr;
    
    (* ram_style = "block" *)
    reg [3:0] memory [0:FRAME_SIZE-1];
    
    assign valid_rd_addr = (read_x < FRAME_WIDTH) & (read_y < FRAME_HEIGHT);
    assign valid_wr_addr = (write_x < FRAME_WIDTH) & (write_y < FRAME_HEIGHT);
    
    assign rd_addr = (read_y * FRAME_WIDTH) + read_x;
    assign wr_addr = (write_y * FRAME_WIDTH) + write_x;
    
    // Reading logic
    always @(posedge read_clk) 
    begin: READ_PROCESS
        if (reset) 
            data_out <= 0;
        else if (read_en & valid_rd_addr) begin
            data_out <= memory[rd_addr];
        end
    end
    
    // Writing Logic
    always @(posedge write_clk)
    begin: WRITE_PROCESS
        if (write_en & valid_wr_addr & !reset) begin 
            memory[wr_addr] <= data_in;
        end
    end
    
    
endmodule
