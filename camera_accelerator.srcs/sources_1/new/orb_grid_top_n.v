`timescale 1ns / 1ps

// Score tracker for one image-grid cell. Coordinates live in the shared BRAM;
// only scores and storage-slot IDs are duplicated here so a full cell can
// decide in one cycle whether a new candidate belongs in its top-N set.
module orb_grid_cell_tracker #(
    parameter integer TOP_N = 8,
    parameter integer COUNT_WIDTH = $clog2(TOP_N + 1),
    parameter integer SLOT_WIDTH = (TOP_N <= 1) ? 1 : $clog2(TOP_N)
) (
    input  wire                   clk,
    input  wire                   reset,
    input  wire                   frame_start,
    input  wire                   candidate_valid,
    input  wire [7:0]             candidate_score,
    output reg                    candidate_accept,
    output reg  [SLOT_WIDTH-1:0]  candidate_slot,
    output reg  [COUNT_WIDTH-1:0] count
);
    reg [7:0] scores [0:TOP_N-1];
    reg [SLOT_WIDTH-1:0] slots [0:TOP_N-1];
    // Descending score, then ascending physical slot. Thus the last entry
    // is the weakest score and highest tied slot, exactly the original rule.
    // Parallel insertion compares only adjacent entries, avoiding a full
    // minimum-reduction tree in the per-candidate feedback path.
    wire [TOP_N-1:0] insert_before;
    genvar rank;
    generate for (rank=0; rank<TOP_N; rank=rank+1) begin: ranks
        assign insert_before[rank] = (count <= rank) ||
            (candidate_score > scores[rank]) ||
            ((candidate_score == scores[rank]) && (candidate_slot < slots[rank]));
        if (rank==0) begin
            always @(posedge clk)
                if (!reset && !frame_start && candidate_accept && insert_before[0]) begin
                    scores[0] <= candidate_score;
                    slots[0] <= candidate_slot;
                end
        end else begin
            always @(posedge clk)
                if (!reset && !frame_start && candidate_accept && insert_before[rank]) begin
                    if (insert_before[rank-1]) begin
                        scores[rank] <= scores[rank-1];
                        slots[rank] <= slots[rank-1];
                    end else begin
                        scores[rank] <= candidate_score;
                        slots[rank] <= candidate_slot;
                    end
                end
        end
    end endgenerate

    always @* begin
        candidate_accept = 1'b0;
        candidate_slot = 0;

        if (candidate_valid) begin
            if (count < TOP_N) begin
                candidate_accept = 1'b1;
                candidate_slot = count[SLOT_WIDTH-1:0];
            end else if (candidate_score > scores[TOP_N-1]) begin
                candidate_accept = 1'b1;
                candidate_slot = slots[TOP_N-1];
            end
        end

    end

    always @(posedge clk) begin
        if (reset || frame_start) begin
            count <= 0;
        end else if (candidate_accept && count < TOP_N)
            count <= count + 1'b1;
    end
endmodule


// Grid-based top-N feature selector. One shared BRAM stores {x,y,score}; small
// per-cell trackers retain sorted scores/slot IDs. Output order is cell-major and then
// slot-major. Membership, rather than score order, is the ORB requirement.
module orb_grid_top_n #(
    parameter integer FRAME_WIDTH  = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer GRID_COLS    = 8,
    parameter integer GRID_ROWS    = 6,
    parameter integer TOP_N        = 8
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       frame_start,
    input  wire       frame_done,
    input  wire       kp_valid,
    input  wire [9:0] kp_x,
    input  wire [8:0] kp_y,
    input  wire [7:0] kp_score,
    output reg        selected_valid,
    input  wire       selected_ready,
    output reg  [9:0] selected_x,
    output reg  [8:0] selected_y,
    output reg  [7:0] selected_score,
    output reg        selection_done,
    output wire       busy
);
    localparam integer CELL_COUNT = GRID_COLS * GRID_ROWS;
    localparam integer CELL_WIDTH = (FRAME_WIDTH + GRID_COLS - 1) / GRID_COLS;
    localparam integer CELL_HEIGHT = (FRAME_HEIGHT + GRID_ROWS - 1) / GRID_ROWS;
    localparam integer COUNT_WIDTH = $clog2(TOP_N + 1);
    localparam integer SLOT_WIDTH = (TOP_N <= 1) ? 1 : $clog2(TOP_N);
    localparam integer CELL_INDEX_WIDTH = (CELL_COUNT <= 1) ? 1 : $clog2(CELL_COUNT);
    localparam integer ENTRY_COUNT = CELL_COUNT * TOP_N;
    localparam integer ENTRY_ADDR_WIDTH = (ENTRY_COUNT <= 1) ? 1 : $clog2(ENTRY_COUNT);
    localparam integer ENTRY_WIDTH = 27;

    wire [CELL_COUNT*COUNT_WIDTH-1:0] cell_counts;
    wire [CELL_COUNT-1:0] cell_accepts;
    wire [CELL_COUNT*SLOT_WIDTH-1:0] cell_slots;

    integer candidate_col;
    integer candidate_row;
    integer candidate_cell;
    reg [CELL_INDEX_WIDTH-1:0] candidate_cell_q;
    reg candidate_valid_q;
    reg [9:0] candidate_x_q;
    reg [8:0] candidate_y_q;
    reg [7:0] candidate_score_q;
    reg frame_done_q, frame_done_qq;
    integer mux_index;
    reg candidate_accept_mux;
    reg [SLOT_WIDTH-1:0] candidate_slot_mux;
    reg [COUNT_WIDTH-1:0] emit_cell_count;

    reg emitting;
    reg draining;
    reg [CELL_INDEX_WIDTH-1:0] emit_cell;
    // COUNT_WIDTH is intentional: the scanner must represent TOP_N itself to
    // recognize that every valid slot in a full cell has been requested.
    reg [COUNT_WIDTH-1:0] emit_slot;

    reg entry_write_en;
    reg [ENTRY_ADDR_WIDTH-1:0] entry_write_addr;
    reg [ENTRY_WIDTH-1:0] entry_write_data;
    wire entry_read_en;
    wire [ENTRY_ADDR_WIDTH-1:0] entry_read_addr;
    reg [ENTRY_WIDTH-1:0] entry_read_data;
    reg entry_read_valid;

    (* ram_style = "block" *)
    reg [ENTRY_WIDTH-1:0] feature_entries [0:ENTRY_COUNT-1];

    assign busy = emitting || draining || frame_done_q || frame_done_qq;

    // Separate coordinate division, tracker/mux selection, and the physical
    // BRAM write. Trackers still accept one candidate per cycle, including
    // consecutive candidates in the same cell. Drain both stages at EOF.
    always @(posedge clk) begin
        if (reset || frame_start) begin
            candidate_valid_q <= 0;
            candidate_cell_q <= 0;
            candidate_x_q <= 0; candidate_y_q <= 0; candidate_score_q <= 0;
            frame_done_q <= 0; frame_done_qq <= 0;
            entry_write_en <= 0; entry_write_addr <= 0; entry_write_data <= 0;
        end else begin
            candidate_valid_q <= kp_valid && !busy;
            candidate_cell_q <= candidate_cell;
            candidate_x_q <= kp_x; candidate_y_q <= kp_y;
            candidate_score_q <= kp_score;
            frame_done_q <= frame_done && !busy;
            frame_done_qq <= frame_done_q;
            entry_write_en <= candidate_valid_q && !emitting && !draining && candidate_accept_mux;
            entry_write_addr <= candidate_cell_q * TOP_N + candidate_slot_mux;
            entry_write_data <= {candidate_x_q, candidate_y_q, candidate_score_q};
        end
    end

    always @* begin
        candidate_col = kp_x / CELL_WIDTH;
        candidate_row = kp_y / CELL_HEIGHT;
        if (candidate_col >= GRID_COLS)
            candidate_col = GRID_COLS - 1;
        if (candidate_row >= GRID_ROWS)
            candidate_row = GRID_ROWS - 1;
        candidate_cell = candidate_row * GRID_COLS + candidate_col;

        candidate_accept_mux = 1'b0;
        candidate_slot_mux = 0;
        emit_cell_count = 0;
        for (mux_index = 0; mux_index < CELL_COUNT;
             mux_index = mux_index + 1) begin
            if (candidate_cell_q == mux_index) begin
                candidate_accept_mux = cell_accepts[mux_index];
                candidate_slot_mux =
                    cell_slots[mux_index*SLOT_WIDTH +: SLOT_WIDTH];
            end
            if (emit_cell == mux_index)
                emit_cell_count =
                    cell_counts[mux_index*COUNT_WIDTH +: COUNT_WIDTH];
        end
    end

    genvar cell_index;
    generate
        for (cell_index = 0; cell_index < CELL_COUNT;
             cell_index = cell_index + 1) begin : trackers
            orb_grid_cell_tracker #(
                .TOP_N(TOP_N), .COUNT_WIDTH(COUNT_WIDTH),
                .SLOT_WIDTH(SLOT_WIDTH)
            ) tracker (
                .clk(clk), .reset(reset), .frame_start(frame_start),
                .candidate_valid(candidate_valid_q && !emitting && !draining &&
                                 (candidate_cell_q == cell_index)),
                .candidate_score(candidate_score_q),
                .candidate_accept(cell_accepts[cell_index]),
                .candidate_slot(
                    cell_slots[cell_index*SLOT_WIDTH +: SLOT_WIDTH]),
                .count(cell_counts[cell_index*COUNT_WIDTH +: COUNT_WIDTH])
            );
        end
    endgenerate

    assign entry_read_en = emitting && (emit_slot < emit_cell_count) &&
                           !entry_read_valid && !selected_valid;
    assign entry_read_addr = emit_cell * TOP_N + emit_slot;

    // Collection writes and end-of-frame emission reads never overlap. This
    // form infers a single BRAM with synchronous read latency.
    always @(posedge clk) begin
        if (entry_write_en && !reset && !frame_start)
            feature_entries[entry_write_addr] <= entry_write_data;

        if (entry_read_en)
            entry_read_data <= feature_entries[entry_read_addr];

        if (reset || frame_start)
            entry_read_valid <= 1'b0;
        else
            entry_read_valid <= entry_read_en;
    end

    always @(posedge clk) begin
        if (reset || frame_start) begin
            selected_valid <= 1'b0;
            selected_x <= 0;
            selected_y <= 0;
            selected_score <= 0;
            selection_done <= 1'b0;
            emitting <= 1'b0;
            draining <= 1'b0;
            emit_cell <= 0;
            emit_slot <= 0;
        end else begin
            selection_done <= 1'b0;

            if (selected_valid && selected_ready)
                selected_valid <= 1'b0;

            if (entry_read_valid) begin
                selected_valid <= 1'b1;
                selected_x <= entry_read_data[26:17];
                selected_y <= entry_read_data[16:8];
                selected_score <= entry_read_data[7:0];
            end

            if (emitting) begin
                if (entry_read_en) begin
                    emit_slot <= emit_slot + 1'b1;
                end else if ((emit_slot >= emit_cell_count) &&
                             !entry_read_valid && !selected_valid &&
                             (emit_cell == CELL_COUNT - 1)) begin
                    emitting <= 1'b0;
                    draining <= 1'b1;
                end else if ((emit_slot >= emit_cell_count) &&
                             !entry_read_valid && !selected_valid) begin
                    emit_cell <= emit_cell + 1'b1;
                    emit_slot <= 0;
                end
            end else if (draining) begin
                if (!entry_read_valid && !selected_valid) begin
                    draining <= 1'b0;
                    selection_done <= 1'b1;
                end
            end else if (frame_done_qq) begin
                emitting <= 1'b1;
                emit_cell <= 0;
                emit_slot <= 0;
            end
        end
    end
endmodule
