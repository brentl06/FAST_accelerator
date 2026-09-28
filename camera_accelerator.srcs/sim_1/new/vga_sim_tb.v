`timescale 1ns / 1ps

module vga_driver_tb;

    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;
    localparam V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;
    localparam FRAME_CYCLES = H_TOTAL * V_TOTAL;

    reg write_clk;
    reg vga_clk;
    reg fb_reset;
    reg vga_reset;
    reg [9:0] write_x;
    reg [8:0] write_y;
    reg [3:0] write_data;
    reg write_en;

    wire [9:0] read_x;
    wire [8:0] read_y;
    wire read_en;
    wire [3:0] pixel_data;
    wire [3:0] red;
    wire [3:0] green;
    wire [3:0] blue;
    wire hsync;
    wire vsync;

    integer x;
    integer y;
    integer cycle;
    integer errors;
    integer model_h;
    integer model_v;
    reg expected_hsync;
    reg expected_vsync;
    reg [3:0] expected_pixel;

    always #5  write_clk = ~write_clk; // 100 MHz write clock
    always #20 vga_clk   = ~vga_clk;   // 25 MHz VGA pixel clock

    function [3:0] test_pattern;
        input [9:0] x_coord;
        input [8:0] y_coord;
        begin
            test_pattern = x_coord[3:0] ^ y_coord[3:0];
        end
    endfunction

    frame_buffer framebuffer (
        .write_clk(write_clk),
        .write_x(write_x),
        .write_y(write_y),
        .data_in(write_data),
        .write_en(write_en),
        .read_clk(vga_clk),
        .read_x(read_x),
        .read_y(read_y),
        .read_en(read_en),
        .data_out(pixel_data),
        .reset(fb_reset)
    );

    vga_driver driver (
        .vga_clk(vga_clk),
        .reset(vga_reset),
        .pixel_in(pixel_data),
        .Red(red),
        .Green(green),
        .Blue(blue),
        .hsync(hsync),
        .vsync(vsync),
        .rd_addr_x(read_x),
        .rd_addr_y(read_y),
        .read_en(read_en)
    );

    task record_error;
        input [8*80-1:0] message;
        begin
            errors = errors + 1;
            if (errors <= 20)
                $display("ERROR t=%0t h=%0d v=%0d: %0s",
                         $time, model_h, model_v, message);
        end
    endtask

    initial begin
        write_clk = 0;
        vga_clk = 0;
        fb_reset = 1;
        vga_reset = 1;
        write_x = 0;
        write_y = 0;
        write_data = 0;
        write_en = 0;
        errors = 0;
        model_h = 0;
        model_v = 0;

        // Reset the framebuffer output, then fill the complete memory through
        // its normal write interface while the VGA scanner remains in reset.
        repeat (3) @(posedge write_clk);
        fb_reset = 0;

        for (y = 0; y < V_VISIBLE; y = y + 1) begin
            for (x = 0; x < H_VISIBLE; x = x + 1) begin
                @(negedge write_clk);
                write_x = x;
                write_y = y;
                write_data = test_pattern(x, y);
                write_en = 1;
            end
        end
        @(negedge write_clk);
        write_en = 0;

        // An invalid write must not alias address zero.
        write_x = H_VISIBLE;
        write_y = 0;
        write_data = 4'hf;
        write_en = 1;
        @(negedge write_clk);
        write_en = 0;

        // Check a complete frame plus the first pixel after frame wrap.
        @(negedge vga_clk);
        vga_reset = 0;

        for (cycle = 0; cycle <= FRAME_CYCLES; cycle = cycle + 1) begin
            // These signals select the framebuffer value captured at the next
            // rising edge of vga_clk.
            if ((model_h < H_VISIBLE) && (model_v < V_VISIBLE)) begin
                if (!read_en)
                    record_error("read_en low during active video");
                if (read_x !== model_h[9:0])
                    record_error("incorrect read_x");
                if (read_y !== model_v[8:0])
                    record_error("incorrect read_y");
            end else if (read_en) begin
                record_error("read_en high during blanking");
            end

            @(posedge vga_clk);
            #1;

            expected_hsync = !((model_h >= H_VISIBLE + H_FRONT) &&
                               (model_h < H_VISIBLE + H_FRONT + H_SYNC));
            expected_vsync = !((model_v >= V_VISIBLE + V_FRONT) &&
                               (model_v < V_VISIBLE + V_FRONT + V_SYNC));

            if ((model_h < H_VISIBLE) && (model_v < V_VISIBLE))
                expected_pixel = test_pattern(model_h, model_v);
            else
                expected_pixel = 0;

            if (hsync !== expected_hsync)
                record_error("incorrect hsync");
            if (vsync !== expected_vsync)
                record_error("incorrect vsync");
            if ((red !== expected_pixel) ||
                (green !== expected_pixel) ||
                (blue !== expected_pixel))
                record_error("incorrect RGB pixel");

            if (model_h == H_TOTAL-1) begin
                model_h = 0;
                if (model_v == V_TOTAL-1)
                    model_v = 0;
                else
                    model_v = model_v + 1;
            end else begin
                model_h = model_h + 1;
            end

            @(negedge vga_clk);
        end

        if (errors == 0)
            $display("PASS: framebuffer and VGA verified for one complete 640x480 frame");
        else
            $fatal(1, "FAIL: %0d errors", errors);

        $finish;
    end

endmodule
