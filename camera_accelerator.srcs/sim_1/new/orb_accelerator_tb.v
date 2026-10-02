`timescale 1ns/1ps
module orb_accelerator_tb #(parameter SHARED=0);
    reg clk=0, reset=1, pixel_valid=0, frame_start=0, ready=0;
    reg [7:0] pixel=0;
    wire frame_ready, dropped, valid, done, completed_valid, bank;
    wire [31:0] dropped_count, frame_id, aborted_count;
    wire [63:0] timestamp;
    wire [255:0] descriptor;
    wire [4:0] angle;
    wire [9:0] x;
    wire [8:0] y;
    wire [7:0] score;
    wire [15:0] count;
    reg [7:0] images[0:12287];
    reg [255:0] held;
    reg [63:0] held_time;
    integer f, outputs=0, cycles=0, done_count=0;
    integer partial_pixel;
    always #5 clk=~clk;
    wire ext_valid, ext_done;
    wire [9:0] ext_x;
    wire [8:0] ext_y;
    wire [7:0] ext_score;
    generate if(SHARED) begin: external_detector
        fast_pipeline_top #(.FRAME_WIDTH(64),.FRAME_HEIGHT(64)) fast (
            .clk(clk),.reset(reset),.pixel_in(pixel),.pixel_valid(pixel_valid),
            .frame_start(frame_start),.threshold(8'd20),.pixel_out(),.keypoint_out(),
            .x(),.y(),.write_en(),.frame_done(ext_done),.kp_valid(ext_valid),
            .kp_x(ext_x),.kp_y(ext_y),.kp_score(ext_score),
            .frame_keypoints(),.frame_keypoints_bcd());
    end else begin
        assign ext_valid=0; assign ext_done=0;
        assign ext_x=0; assign ext_y=0; assign ext_score=0;
    end endgenerate
    orb_accelerator #(.FRAME_WIDTH(64),.FRAME_HEIGHT(64),.GRID_COLS(2),.GRID_ROWS(2),.TOP_N(2),.EXTERNAL_FAST(SHARED)) dut (
        .clk(clk),.reset(reset),.pixel_in(pixel),.pixel_valid(pixel_valid),
        .frame_start(frame_start),.fast_threshold(8'd20),.frame_ready(frame_ready),
        .external_kp_valid(ext_valid),.external_fast_done(ext_done),
        .external_kp_x(ext_x),.external_kp_y(ext_y),.external_kp_score(ext_score),
        .frame_dropped(dropped),.dropped_frames(dropped_count),.descriptor_valid(valid),
        .aborted_frames(aborted_count),
        .descriptor_ready(ready),.descriptor(descriptor),.angle_bin(angle),
        .feature_x(x),.feature_y(y),.feature_score(score),.feature_frame_id(frame_id),
        .feature_timestamp(timestamp),.frame_done(done),.frame_feature_count(count),
        .completed_frame_valid(completed_valid),.completed_frame_bank(bank));
    always @(posedge clk) begin
        cycles <= cycles+1;
        if(valid && ready) begin
            $fdisplay(f,"%0d %0d %0d %0d %0d %h",frame_id,x,y,score,angle,descriptor);
            outputs=outputs+1;
        end
        if(done) begin
            done_count=done_count+1;
            if(count !== outputs) $fatal(1,"frame feature count wrong");
            outputs=0;
        end
    end
    task send_frame;
        input integer image;
        integer i;
        begin
            for(i=0;i<4096;i=i+1) begin
                @(negedge clk); pixel=images[image*4096+i]; pixel_valid=1; frame_start=(i==0);
                if(i%11==0) begin
                    @(negedge clk); pixel_valid=0; frame_start=0;
                end
            end
            @(negedge clk); pixel_valid=0; frame_start=0;
        end
    endtask
    initial begin
        #8000000;
        $display("timeout state=%0d raw=%b fast=%b sel_busy=%b selected=%b reader=%0d engine=%0d done_count=%0d",
            dut.state,dut.raw_finished,dut.fast_finished,dut.frontend.selector_busy,
            dut.frontend.selected_valid,dut.frontend.reader.state,dut.frontend.engine.state,done_count);
        $fatal(1,"accelerator timeout");
    end
    initial begin
        $readmemh("frames.hex",images);
        f=$fopen("accelerator_actual.txt","w");
        repeat(4) @(negedge clk); reset=0;
        send_frame(0);
        wait(valid); @(negedge clk);
        held=descriptor; held_time=timestamp;
        // Entire next camera frame arrives while descriptor output is stalled.
        send_frame(1);
        if(!valid || descriptor !== held || timestamp !== held_time || frame_ready)
            $fatal(1,"frame ownership/output not stable under backpressure");
        if(dropped_count != 1) $fatal(1,"busy frame not counted as dropped");
        ready=1;
        wait(frame_ready); @(negedge clk);
        if(!completed_valid || bank !== 0) $fatal(1,"first completed bank incorrect");
        send_frame(1);
        wait(frame_ready); @(negedge clk);
        if(bank !== 1) $fatal(1,"second frame did not alternate banks");
        send_frame(2);
        wait(frame_ready); @(negedge clk);
        if(bank !== 0 || count != 0 || done_count != 3) $fatal(1,"empty frame completion failed");
        // Abort an incomplete capture, reject the new marker's frame, and
        // recover on the following complete frame without modifying bank 0.
        for(partial_pixel=0;partial_pixel<25;partial_pixel=partial_pixel+1) begin
            @(negedge clk); pixel_valid=1; frame_start=(partial_pixel==0); pixel=8'hff;
        end
        @(negedge clk); pixel_valid=0; frame_start=0;
        send_frame(2);
        if(aborted_count != 1 || dropped_count != 2 || !frame_ready || bank !== 0)
            $fatal(1,"interrupted capture recovery failed");
        send_frame(2);
        wait(frame_ready); @(negedge clk);
        if(bank !== 1 || count != 0 || done_count != 4) $fatal(1,"post-abort frame failed");
        $fclose(f);
        $display("PASS: connected FAST to descriptors, bank alternation, drop/stall, empty frames, interrupted capture recovery");
        $finish;
    end
endmodule

module orb_accelerator_shared_tb;
    orb_accelerator_tb #(.SHARED(1)) test();
endmodule
