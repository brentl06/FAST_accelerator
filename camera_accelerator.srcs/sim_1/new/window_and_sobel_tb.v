`timescale 1ns / 1ps

// Integration testbench for:
//   pixel stream -> sliding_window -> sobel_filter
//
// Four 9x9 test images are generated:
//   0. Constant gray
//   1. Vertical step edge
//   2. Horizontal step edge
//   3. Diagonal step edge
//
// The testbench writes a 9x9 input PGM and a 7x7 Sobel PGM for each case.
// A 7x7 output is expected because only pixels with a complete 3x3
// neighborhood are emitted. A fifth test streams a 640x480 image containing
// a centered white rectangle through a separate 640-pixel-wide DUT instance.

module sobel_sliding_window_tb;

    parameter IMAGE_WIDTH   = 9;
    parameter IMAGE_HEIGHT  = 9;
    parameter OUTPUT_WIDTH  = IMAGE_WIDTH - 2;
    parameter OUTPUT_HEIGHT = IMAGE_HEIGHT - 2;
    parameter OUTPUT_PIXELS = OUTPUT_WIDTH * OUTPUT_HEIGHT;

    parameter LARGE_WIDTH         = 640;
    parameter LARGE_HEIGHT        = 480;
    parameter LARGE_OUTPUT_WIDTH  = LARGE_WIDTH - 2;
    parameter LARGE_OUTPUT_HEIGHT = LARGE_HEIGHT - 2;
    parameter LARGE_OUTPUT_PIXELS = LARGE_OUTPUT_WIDTH * LARGE_OUTPUT_HEIGHT;

    reg       clk;
    reg       reset;
    reg [7:0] pixel;
    reg       pixel_valid;

    wire [7:0] w00, w01, w02;
    wire [7:0] w10, w11, w12;
    wire [7:0] w20, w21, w22;
    wire       window_valid;

    wire       out_valid;
    wire       edge_detected;

    reg [7:0] test_image [0:IMAGE_WIDTH*IMAGE_HEIGHT-1];

    integer row;
    integer col;
    integer index;
    integer test_id;
    integer input_file;
    integer output_file;
    integer output_count;
    integer window_count;
    integer timeout_count;
    reg     capture_enable;

    // Signals and counters for the separately parameterized 640x480 pipeline.
    reg        reset_640;
    reg  [7:0] pixel_640;
    reg        pixel_valid_640;

    wire [7:0] w00_640, w01_640, w02_640;
    wire [7:0] w10_640, w11_640, w12_640;
    wire [7:0] w20_640, w21_640, w22_640;
    wire       window_valid_640;
    wire       out_valid_640;
    wire       edge_detected_640;

    integer row_640;
    integer col_640;
    integer input_file_640;
    integer output_file_640;
    integer output_count_640;
    integer window_count_640;
    integer timeout_count_640;
    reg     capture_enable_640;

    // Change IMAGE_WIDTH below if the width parameter in your module has a
    // different name, for example WIDTH or FRAME_WIDTH.
    sliding_window #(
        .IMAGE_WIDTH(IMAGE_WIDTH)
    ) window_dut (
        .clk(clk),
        .reset(reset),
        .pixel(pixel),
        .pixel_valid(pixel_valid),
        .w00(w00), .w01(w01), .w02(w02),
        .w10(w10), .w11(w11), .w12(w12),
        .w20(w20), .w21(w21), .w22(w22),
        .window_valid(window_valid)
    );

    sobel_filter #(
        .EDGE_THRESHOLD(11'd300)
    ) sobel_dut (
        .clk(clk),
        .reset(reset),
        .window_valid(window_valid),
        .w00(w00), .w01(w01), .w02(w02),
        .w10(w10), .w11(w11), .w12(w12),
        .w20(w20), .w21(w21), .w22(w22),
        .out_valid(out_valid),
        .edge_detected(edge_detected)
    );

    // A second DUT instance is necessary because IMAGE_WIDTH is fixed at
    // elaboration time and cannot change from 9 to 640 during simulation.
    sliding_window #(
        .IMAGE_WIDTH(LARGE_WIDTH)
    ) window_dut_640 (
        .clk(clk),
        .reset(reset_640),
        .pixel(pixel_640),
        .pixel_valid(pixel_valid_640),
        .w00(w00_640), .w01(w01_640), .w02(w02_640),
        .w10(w10_640), .w11(w11_640), .w12(w12_640),
        .w20(w20_640), .w21(w21_640), .w22(w22_640),
        .window_valid(window_valid_640)
    );

    sobel_filter #(
        .EDGE_THRESHOLD(11'd300)
    ) sobel_dut_640 (
        .clk(clk),
        .reset(reset_640),
        .window_valid(window_valid_640),
        .w00(w00_640), .w01(w01_640), .w02(w02_640),
        .w10(w10_640), .w11(w11_640), .w12(w12_640),
        .w20(w20_640), .w21(w21_640), .w22(w22_640),
        .out_valid(out_valid_640),
        .edge_detected(edge_detected_640)
    );

    // 100 MHz clock.
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Fill test_image with one of the four patterns.
    task build_test_image;
        input integer selected_test;
        begin
            for (row = 0; row < IMAGE_HEIGHT; row = row + 1) begin
                for (col = 0; col < IMAGE_WIDTH; col = col + 1) begin
                    index = row * IMAGE_WIDTH + col;

                    case (selected_test)
                        // Test 0: constant image. Sobel should find no edges.
                        0: test_image[index] = 8'd100;

                        // Test 1: vertical black-to-white step.
                        1: begin
                            if (col < 4)
                                test_image[index] = 8'd0;
                            else
                                test_image[index] = 8'd255;
                        end

                        // Test 2: horizontal black-to-white step.
                        2: begin
                            if (row < 4)
                                test_image[index] = 8'd0;
                            else
                                test_image[index] = 8'd255;
                        end

                        // Test 3: diagonal black-to-white step.
                        3: begin
                            if (col >= row)
                                test_image[index] = 8'd255;
                            else
                                test_image[index] = 8'd0;
                        end

                        default: test_image[index] = 8'd0;
                    endcase
                end
            end
        end
    endtask

    // Open the input and output image files for the selected test.
    task open_test_files;
        input integer selected_test;
        begin
            case (selected_test)
                0: begin
                    input_file  = $fopen("input_constant.pgm", "w");
                    output_file = $fopen("sobel_constant.pgm", "w");
                end
                1: begin
                    input_file  = $fopen("input_vertical.pgm", "w");
                    output_file = $fopen("sobel_vertical.pgm", "w");
                end
                2: begin
                    input_file  = $fopen("input_horizontal.pgm", "w");
                    output_file = $fopen("sobel_horizontal.pgm", "w");
                end
                3: begin
                    input_file  = $fopen("input_diagonal.pgm", "w");
                    output_file = $fopen("sobel_diagonal.pgm", "w");
                end
            endcase

            if ((input_file == 0) || (output_file == 0)) begin
                $display("ERROR: Could not open PGM output files.");
                $finish;
            end

            $fwrite(input_file, "P2\n");
            $fwrite(input_file, "%0d %0d\n", IMAGE_WIDTH, IMAGE_HEIGHT);
            $fwrite(input_file, "255\n");

            $fwrite(output_file, "P2\n");
            $fwrite(output_file, "%0d %0d\n", OUTPUT_WIDTH, OUTPUT_HEIGHT);
            $fwrite(output_file, "255\n");
        end
    endtask

    task reset_pipeline;
        begin
            capture_enable = 1'b0;
            pixel_valid    = 1'b0;
            pixel          = 8'd0;
            reset          = 1'b1;

            repeat (3) @(posedge clk);
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    // Send one complete 9x9 image, one pixel per clock.
    task stream_test_image;
        begin
            for (row = 0; row < IMAGE_HEIGHT; row = row + 1) begin
                for (col = 0; col < IMAGE_WIDTH; col = col + 1) begin
                    index = row * IMAGE_WIDTH + col;

                    @(negedge clk);
                    pixel       = test_image[index];
                    pixel_valid = 1'b1;

                    $fwrite(input_file, "%0d ", test_image[index]);
                end
                $fwrite(input_file, "\n");
            end

            @(negedge clk);
            pixel_valid = 1'b0;
            pixel       = 8'd0;
        end
    endtask

    task run_test;
        input integer selected_test;
        begin
            $display("----------------------------------------");
            $display("Starting test %0d", selected_test);

            reset_pipeline;
            build_test_image(selected_test);
            open_test_files(selected_test);

            test_id        = selected_test;
            output_count   = 0;
            window_count   = 0;
            timeout_count  = 0;
            capture_enable = 1'b1;

            stream_test_image;

            // Wait for all 49 valid Sobel results, with a timeout so a broken
            // valid pipeline does not leave the simulation running forever.
            while ((output_count < OUTPUT_PIXELS) &&
                   (timeout_count < 40)) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end

            #2;
            capture_enable = 1'b0;

            if (output_count != OUTPUT_PIXELS) begin
                $display("ERROR: Test %0d produced %0d outputs; expected %0d.",
                         selected_test, output_count, OUTPUT_PIXELS);
                $display("Check window_valid, g_valid, and out_valid timing.");
            end
            else begin
                $display("PASS: Test %0d produced %0d output pixels.",
                         selected_test, output_count);
            end

            if (window_count != OUTPUT_PIXELS) begin
                $display("ERROR: sliding_window produced %0d windows; expected %0d.",
                         window_count, OUTPUT_PIXELS);
            end

            $fclose(input_file);
            $fclose(output_file);
        end
    endtask

    // Test 4: stream a full 640x480 synthetic image. The image is black with
    // a white rectangle spanning columns 160-479 and rows 120-359. The Sobel
    // result should show a two-pixel-wide rectangular outline.
    task run_640x480_test;
        begin
            $display("----------------------------------------");
            $display("Starting test 4: 640x480 centered rectangle");

            capture_enable_640 = 1'b0;
            pixel_valid_640    = 1'b0;
            pixel_640          = 8'd0;
            reset_640          = 1'b1;

            repeat (3) @(posedge clk);
            @(negedge clk);
            reset_640 = 1'b0;

            input_file_640  = $fopen("input_640x480_rectangle.pgm", "w");
            output_file_640 = $fopen("sobel_638x478_rectangle.pgm", "w");

            if ((input_file_640 == 0) || (output_file_640 == 0)) begin
                $display("ERROR: Could not open 640x480 PGM files.");
                $finish;
            end

            $fwrite(input_file_640, "P2\n");
            $fwrite(input_file_640, "%0d %0d\n",
                    LARGE_WIDTH, LARGE_HEIGHT);
            $fwrite(input_file_640, "255\n");

            $fwrite(output_file_640, "P2\n");
            $fwrite(output_file_640, "%0d %0d\n",
                    LARGE_OUTPUT_WIDTH, LARGE_OUTPUT_HEIGHT);
            $fwrite(output_file_640, "255\n");

            output_count_640  = 0;
            window_count_640  = 0;
            timeout_count_640 = 0;
            capture_enable_640 = 1'b1;

            for (row_640 = 0; row_640 < LARGE_HEIGHT;
                 row_640 = row_640 + 1) begin
                for (col_640 = 0; col_640 < LARGE_WIDTH;
                     col_640 = col_640 + 1) begin
                    @(negedge clk);

                    if ((row_640 >= 120) && (row_640 < 360) &&
                        (col_640 >= 160) && (col_640 < 480))
                        pixel_640 = 8'd255;
                    else
                        pixel_640 = 8'd0;

                    pixel_valid_640 = 1'b1;
                    $fwrite(input_file_640, "%0d ", pixel_640);
                end

                $fwrite(input_file_640, "\n");
            end

            @(negedge clk);
            pixel_valid_640 = 1'b0;
            pixel_640       = 8'd0;

            // Only a few clocks should be required to flush the pipeline, but
            // allow extra time to make failures easy to diagnose.
            while ((output_count_640 < LARGE_OUTPUT_PIXELS) &&
                   (timeout_count_640 < 1000)) begin
                @(posedge clk);
                timeout_count_640 = timeout_count_640 + 1;
            end

            #2;
            capture_enable_640 = 1'b0;

            if (window_count_640 != LARGE_OUTPUT_PIXELS) begin
                $display("ERROR: 640-wide sliding_window produced %0d windows; expected %0d.",
                         window_count_640, LARGE_OUTPUT_PIXELS);
            end

            if (output_count_640 != LARGE_OUTPUT_PIXELS) begin
                $display("ERROR: 640x480 Sobel produced %0d outputs; expected %0d.",
                         output_count_640, LARGE_OUTPUT_PIXELS);
            end
            else begin
                $display("PASS: 640x480 test produced %0d output pixels.",
                         output_count_640);
            end

            $fclose(input_file_640);
            $fclose(output_file_640);
        end
    endtask

    // Capture the connected pipeline output. The #1 delay allows registered
    // DUT outputs to update after the rising clock edge.
    always @(posedge clk) begin
        #1;

        if (capture_enable && window_valid) begin
            window_count = window_count + 1;

            // Print the first three windows from each test for visual checking.
            if (window_count <= 3) begin
                $display("Test %0d, window %0d:", test_id, window_count);
                $display("  %3d %3d %3d", w00, w01, w02);
                $display("  %3d %3d %3d", w10, w11, w12);
                $display("  %3d %3d %3d", w20, w21, w22);
            end
        end

        if (capture_enable && out_valid) begin
            if (edge_detected)
                $fwrite(output_file, "255 ");
            else
                $fwrite(output_file, "0 ");

            output_count = output_count + 1;

            if ((output_count % OUTPUT_WIDTH) == 0)
                $fwrite(output_file, "\n");
        end
    end

    // Capture the full-resolution pipeline without printing every window.
    always @(posedge clk) begin
        #1;

        if (capture_enable_640 && window_valid_640)
            window_count_640 = window_count_640 + 1;

        if (capture_enable_640 && out_valid_640) begin
            if (edge_detected_640)
                $fwrite(output_file_640, "255 ");
            else
                $fwrite(output_file_640, "0 ");

            output_count_640 = output_count_640 + 1;

            if ((output_count_640 % LARGE_OUTPUT_WIDTH) == 0)
                $fwrite(output_file_640, "\n");
        end
    end

    initial begin
        reset          = 1'b1;
        pixel          = 8'd0;
        pixel_valid    = 1'b0;
        capture_enable = 1'b0;
        test_id        = 0;
        input_file     = 0;
        output_file    = 0;
        reset_640          = 1'b1;
        pixel_640          = 8'd0;
        pixel_valid_640    = 1'b0;
        capture_enable_640 = 1'b0;
        input_file_640     = 0;
        output_file_640    = 0;
        output_count_640   = 0;
        window_count_640   = 0;

        run_test(0);
        run_test(1);
        run_test(2);
        run_test(3);
        run_640x480_test;

        $display("----------------------------------------");
        $display("All five integration tests completed.");
        $display("Open the generated .pgm files to inspect the results.");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
