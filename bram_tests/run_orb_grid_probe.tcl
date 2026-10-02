read_verilog camera_accelerator.srcs/sources_1/new/orb_grid_top_n.v
synth_design -top orb_grid_top_n -part xc7a100tcsg324-1 -mode out_of_context
report_utilization -file bram_tests/orb_grid_top_n_utilization.rpt
