`timescale 1ns / 1ps

// Single-scale, 4-bit ORB variant: radius-15 intensity centroid, 32 angle
// bins, OpenCV's 256 test pairs, and 3x3 binomial smoothing before comparison.
// A 41x41 patch includes the rotated pattern and its smoothing halo.
// Not byte-compatible with OpenCV (quantization, circle mask, and blur differ).
// start clears a transaction; patch pixels follow in raster order. Output is
// held until ready. No patch RAM reset is needed: every patch overwrites it.
module orb_descriptor (
    input wire clk, reset, start,
    input wire patch_valid,
    input wire [3:0] patch_pixel,
    input wire [5:0] patch_col, patch_row,
    input wire patch_done, patch_rejected,
    output wire start_ready,
    output reg descriptor_valid,
    input wire descriptor_ready,
    output reg [255:0] descriptor,
    output reg [4:0] angle_bin,
    output reg rejected
);
    localparam IDLE=0, LOAD=1, ANGLE=2, ROTATE=3, ADDRESS=4,
               READ=5, ACCUM=6, OUTPUT=7, ANGLE_SUM=8, ANGLE_COMPARE=9,
               ROTATE_MULT=10, ROTATE_SUM=11, ROTATE_ROUND=12, SAMPLE_DONE=13;
    reg [3:0] state;
    (* ram_style="block" *) reg [3:0] pixels [0:1680];
    reg [10:0] read_address;
    reg [3:0] read_pixel;
    wire signed [7:0] dx = $signed({1'b0,patch_col}) - 8'sd20;
    wire signed [7:0] dy = $signed({1'b0,patch_row}) - 8'sd20;
    reg in_centroid;
    // Exact integer radius-15 disk, expressed as row bounds instead of two
    // squares and an addition on the accumulator clock-enable path.
    always @* begin
        case (patch_row)
            5,35: in_centroid = patch_col == 20;
            6,34: in_centroid = patch_col >= 15 && patch_col <= 25;
            7,33: in_centroid = patch_col >= 13 && patch_col <= 27;
            8,32: in_centroid = patch_col >= 11 && patch_col <= 29;
            9,31: in_centroid = patch_col >= 10 && patch_col <= 30;
            10,30: in_centroid = patch_col >= 9 && patch_col <= 31;
            11,12,28,29: in_centroid = patch_col >= 8 && patch_col <= 32;
            13,14,26,27: in_centroid = patch_col >= 7 && patch_col <= 33;
            15,16,17,18,19,21,22,23,24,25:
                in_centroid = patch_col >= 6 && patch_col <= 34;
            20: in_centroid = patch_col >= 5 && patch_col <= 35;
            default: in_centroid = 0;
        endcase
    end
    wire signed [12:0] moment_x = dx * $signed({1'b0,patch_pixel});
    wire signed [12:0] moment_y = dy * $signed({1'b0,patch_pixel});
    reg signed [23:0] m10, m01;
    reg [4:0] scan_bin;
    wire signed [11:0] cosine, sine;
    orb_trig trig(.bin(state == ANGLE ? scan_bin : angle_bin),
                  .cosine(cosine), .sine(sine));
    reg signed [35:0] projection_x, projection_y, projection;
    reg signed [35:0] best_projection;
    reg [8:0] sample_index;
    wire signed [4:0] pattern_x, pattern_y;
    orb_pattern pattern(.index(sample_index), .x(pattern_x), .y(pattern_y));
    reg signed [4:0] pattern_x_q, pattern_y_q;
    reg signed [11:0] rotate_cosine, rotate_sine;
    reg signed [16:0] product_xc, product_ys, product_xs, product_yc;
    reg signed [17:0] rotated_x, rotated_y;
    // Round to nearest with ties toward +infinity, defined identically in
    // tools/orb_reference.py. Range is -18..18, leaving a one-pixel halo.
    reg signed [7:0] sample_x, sample_y;
    reg [1:0] blur_x, blur_y;
    wire [1:0] weight_shift = (blur_x == 1) + {1'b0,(blur_y == 1)};
    reg [7:0] sample_sum, first_sum;
    wire [7:0] weighted_pixel = {4'b0,read_pixel} << weight_shift;
    wire [7:0] final_sum = sample_sum + weighted_pixel;
    wire [5:0] blur_col = sample_x + blur_x - 1;
    wire [5:0] blur_row = sample_y + blur_y - 1;
    wire [10:0] row_times_41 = ({5'b0,blur_row} << 5) +
                              ({5'b0,blur_row} << 3) + {5'b0,blur_row};
    assign start_ready = (state == IDLE);

    always @(posedge clk) begin
        if (state == LOAD && patch_valid)
            pixels[patch_row*41 + patch_col] <= patch_pixel;
        if (state == READ)
            read_pixel <= pixels[read_address];
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            descriptor_valid <= 0; descriptor <= 0; angle_bin <= 0;
            rejected <= 0; m10 <= 0; m01 <= 0; scan_bin <= 0;
            best_projection <= 0; sample_index <= 0;
            projection_x <= 0; projection_y <= 0; projection <= 0;
            pattern_x_q <= 0; pattern_y_q <= 0;
            rotate_cosine <= 0; rotate_sine <= 0;
            product_xc <= 0; product_ys <= 0; product_xs <= 0; product_yc <= 0;
            rotated_x <= 0; rotated_y <= 0;
            sample_x <= 0; sample_y <= 0; blur_x <= 0; blur_y <= 0;
            sample_sum <= 0; first_sum <= 0; read_address <= 0;
        end else begin
            rejected <= 0;
            case (state)
                IDLE: if (start) begin
                    m10 <= 0; m01 <= 0; descriptor <= 0;
                    angle_bin <= 0; state <= LOAD;
                end
                LOAD: begin
                    if (patch_valid && in_centroid) begin
                        m10 <= m10 + moment_x;
                        m01 <= m01 + moment_y;
                    end
                    if (patch_done) begin
                        if (patch_rejected) begin rejected <= 1; state <= IDLE; end
                        else begin
                            scan_bin <= 0;
                            best_projection <= -36'sd34359738368;
                            state <= ANGLE;
                        end
                    end
                end
                ANGLE: begin
                    projection_x <= m10*cosine;
                    projection_y <= m01*sine;
                    state <= ANGLE_SUM;
                end
                ANGLE_SUM: begin
                    projection <= projection_x + projection_y;
                    state <= ANGLE_COMPARE;
                end
                ANGLE_COMPARE: begin
                    if (projection > best_projection) begin
                        best_projection <= projection; angle_bin <= scan_bin;
                    end
                    if (scan_bin == 31) begin sample_index <= 0; state <= ROTATE; end
                    else begin scan_bin <= scan_bin + 1'b1; state <= ANGLE; end
                end
                ROTATE: begin
                    // ROM lookup, products, sum and rounding each get their
                    // own cycle; the numerical descriptor definition is unchanged.
                    pattern_x_q <= pattern_x; pattern_y_q <= pattern_y;
                    rotate_cosine <= cosine; rotate_sine <= sine;
                    state <= ROTATE_MULT;
                end
                ROTATE_MULT: begin
                    product_xc <= pattern_x_q * rotate_cosine;
                    product_ys <= pattern_y_q * rotate_sine;
                    product_xs <= pattern_x_q * rotate_sine;
                    product_yc <= pattern_y_q * rotate_cosine;
                    state <= ROTATE_SUM;
                end
                ROTATE_SUM: begin
                    rotated_x <= $signed(product_xc) - $signed(product_ys);
                    rotated_y <= $signed(product_xs) + $signed(product_yc);
                    state <= ROTATE_ROUND;
                end
                ROTATE_ROUND: begin
                    sample_x <= ((rotated_x + 18'sd512) >>> 10) + 20;
                    sample_y <= ((rotated_y + 18'sd512) >>> 10) + 20;
                    blur_x <= 0; blur_y <= 0; sample_sum <= 0;
                    state <= ADDRESS;
                end
                ADDRESS: begin
                    read_address <= row_times_41 + {5'b0,blur_col};
                    state <= READ;
                end
                READ: state <= ACCUM;
                ACCUM: begin
                    sample_sum <= final_sum;
                    if (blur_x == 2 && blur_y == 2) begin
                        if (!sample_index[0]) first_sum <= final_sum;
                        state <= SAMPLE_DONE;
                    end else begin
                        if (blur_x == 2) begin blur_x <= 0; blur_y <= blur_y + 1'b1; end
                        else blur_x <= blur_x + 1'b1;
                        state <= ADDRESS;
                    end
                end
                SAMPLE_DONE: begin
                    // Compare the registered sum, isolating patch BRAM output
                    // and blur accumulation from the 256-bit descriptor mux.
                    if (sample_index[0])
                        descriptor[sample_index[8:1]] <= first_sum < sample_sum;
                    if (sample_index == 511) begin
                        descriptor_valid <= 1; state <= OUTPUT;
                    end else begin sample_index <= sample_index + 1'b1; state <= ROTATE; end
                end
                OUTPUT: if (descriptor_ready) begin descriptor_valid <= 0; state <= IDLE; end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
