# Run from repository root. This measures the connected camera-stream core,
# including two raw framebuffers. It does not change the board project top.
foreach name {frame_buffer test_pipeline line_window fast_score fast_nms fast_detector fast_pipeline_top orb_grid_top_n orb_patch_reader orb_pattern orb_descriptor orb_frontend orb_accelerator} {
    read_verilog camera_accelerator.srcs/sources_1/new/$name.v
}
synth_design -top orb_accelerator -part xc7a100tcsg324-1 -mode out_of_context
create_clock -name sysclk -period 10.000 [get_ports clk]
report_utilization -hierarchical -file bram_tests/orb_accelerator_hierarchy.rpt
report_utilization -file bram_tests/orb_accelerator_utilization.rpt
report_timing_summary -file bram_tests/orb_accelerator_timing_synth.rpt
