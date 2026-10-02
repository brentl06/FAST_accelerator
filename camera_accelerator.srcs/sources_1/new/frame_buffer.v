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
    reg [18:0] wr_addr_q;
    reg [3:0]  wr_data_q;
    reg        wr_en_q;
    
    (* ram_style = "block" *)
    reg [3:0] memory [0:FRAME_SIZE-1];
    integer init_x;
    integer init_y;

    // Give the display deterministic black pixels before camera processing
    // begins. In particular, the Sobel pipeline intentionally never writes the
    // outer one-pixel border.
    initial begin
        for (init_y = 0; init_y < FRAME_HEIGHT; init_y = init_y + 1) begin
            for (init_x = 0; init_x < FRAME_WIDTH; init_x = init_x + 1)
                memory[(init_y * FRAME_WIDTH) + init_x] = 4'h0;
        end
    end
    
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
    
    // Pipeline the complete write request before it reaches the framebuffer.
    // This separates the y * FRAME_WIDTH + x address calculation from the
    // BRAM bank decode and write-enable path while preserving one write per
    // clock throughput.
    always @(posedge write_clk)
    begin: WRITE_PROCESS
        if (reset) begin
            wr_addr_q <= 19'd0;
            wr_data_q <= 4'd0;
            wr_en_q   <= 1'b0;
        end else begin
            wr_en_q <= write_en & valid_wr_addr;

            if (write_en & valid_wr_addr) begin
                wr_addr_q <= wr_addr;
                wr_data_q <= data_in;
            end

            if (wr_en_q)
                memory[wr_addr_q] <= wr_data_q;
        end
    end
    
    
endmodule
