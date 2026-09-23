`timescale 1ns / 1ps

module vga_driver_tb;

    reg clk;
    reg reset;

    wire [7:0] Red;
    wire [7:0] Green;
    wire [7:0] Blue;
    wire hsync;
    wire vsync;

    vga_driver dut (
        .clk   (clk),
        .reset (reset),
        .Red   (Red),
        .Green (Green),
        .Blue  (Blue),
        .hsync (hsync),
        .vsync (vsync)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        reset = 1'b1;
        #100;
        reset = 1'b0;

        #1000;
        $finish;
    end

    initial begin
        $monitor(
            "time=%0t clk=%b reset=%b div=%b vga_clk=%b",
            $time, clk, reset, dut.div_clk, dut.vga_clk
        );
    end

endmodule