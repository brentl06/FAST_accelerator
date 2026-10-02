read_verilog camera_accelerator.srcs/sources_1/new/orb_patch_reader.v
synth_design -top orb_patch_reader -part xc7a100tcsg324-1 -mode out_of_context
report_utilization -file bram_tests/orb_patch_reader_utilization.rpt
