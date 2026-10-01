`timescale 1ns / 1ps

// Streaming N x N neighborhood generator.
//
// The N-1 previous image rows are stored side by side in one BRAM word per
// column, so each input pixel costs exactly one read and one write. Every
// valid input produces exactly one output window two clocks later, in order.
// in_valid may have gaps (the camera delivers ~1 pixel per 8 clocks).
//
// TAG is carried alongside the data with the same latency, so downstream
// logic never has to count pipeline stages to recover coordinates.
//
// out_win is row-major, oldest row first. Element (i, j) is
//     out_win[(i*N + j)*DATA_W +: DATA_W]
// and holds the pixel at (col - (N-1) + j, row - (N-1) + i), where (col, row)
// is the newest input pixel. When col < N-1 or row < N-1 the window holds
// wrapped or previous-frame data; validity is the caller's decision.
module line_window #(
    parameter N      = 3,     // window size, >= 3
    parameter LINE_W = 640,   // pixels per image row
    parameter DATA_W = 8,
    parameter TAG_W  = 1
)(
    input  wire                  clk,
    input  wire                  reset,
    input  wire                  in_valid,
    input  wire [DATA_W-1:0]     in_data,
    input  wire [9:0]            in_col,
    input  wire [TAG_W-1:0]      in_tag,

    output reg                   out_valid,
    output reg  [N*N*DATA_W-1:0] out_win,
    output reg  [TAG_W-1:0]      out_tag
);

    localparam LB_W = (N-1) * DATA_W;

    // lines[c][k*DATA_W +: DATA_W] = column c of row (current - 1 - k)
    (* ram_style = "block" *)
    reg [LB_W-1:0] lines [0:LINE_W-1];

    // Stage A: synchronous BRAM read of the column above the new pixel.
    reg [LB_W-1:0]   rd_q;
    reg              a_valid;
    reg [DATA_W-1:0] a_data;
    reg [9:0]        a_col;
    reg [TAG_W-1:0]  a_tag;

    always @(posedge clk) begin
        if (in_valid) begin
            rd_q   <= lines[in_col];
            a_data <= in_data;
            a_col  <= in_col;
            a_tag  <= in_tag;
        end
    end

    // column[k*DATA_W +: DATA_W] = pixel from row (current - k), k = 0..N-1
    wire [N*DATA_W-1:0] column = {rd_q, a_data};

    // Stage B: push the new pixel into the column (oldest row drops out) and
    // shift the column into the window. Write and next read never share an
    // address: consecutive pixels are in different columns.
    always @(posedge clk) begin
        if (a_valid)
            lines[a_col] <= column[LB_W-1:0];
    end

    integer i, j;
    always @(posedge clk) begin
        if (a_valid) begin
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N-1; j = j + 1)
                    out_win[(i*N + j)*DATA_W +: DATA_W] <=
                        out_win[(i*N + j + 1)*DATA_W +: DATA_W];
                out_win[(i*N + N-1)*DATA_W +: DATA_W] <=
                    column[(N-1-i)*DATA_W +: DATA_W];
            end
            out_tag <= a_tag;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            a_valid   <= 1'b0;
            out_valid <= 1'b0;
        end else begin
            a_valid   <= in_valid;
            out_valid <= a_valid;
        end
    end

endmodule
