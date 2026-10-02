# Isolated board build; preserves the existing project's runs and bitstream.
# Run from repository root with Vivado -mode batch -source tools/build_orb_board.tcl.
if {[llength $argv] != 1} { error "Pass the absolute repository directory with -tclargs" }
set orb_repo [file normalize [lindex $argv 0]]
set orb_build_dir [file join $orb_repo orb_test_output board_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
puts "ORB_BOARD_BUILD_DIRECTORY: $orb_build_dir"
create_project orb_board $orb_build_dir -part xc7a100tcsg324-1
add_files [glob [file join $orb_repo camera_accelerator.srcs sources_1 new *.v]]
add_files [file join $orb_repo camera_accelerator.srcs sources_1 ip fifo_generator_0 fifo_generator_0.xci]
set constraints [file normalize [file join $orb_repo .. OneDrive Documents ChatGPT {FPGA Side Projects} nexys_a7_vga_test.xdc]]
if {![file exists $constraints]} { error "Missing project board constraints: $constraints" }
add_files -fileset constrs_1 [list $constraints]
set_property top vga_test_top [current_fileset]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Board synthesis failed" }
open_run synth_1
report_utilization -hierarchical -file [file join $orb_build_dir board_synth_hierarchy.rpt]
report_utilization -file [file join $orb_build_dir board_synth_utilization.rpt]
if {[llength [get_cells -hier -filter {NAME =~ orb/frontend/engine/*}]] == 0} {
    error "ORB descriptor engine was not retained in board synthesis"
}
close_design
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Board implementation failed" }
open_run impl_1
report_utilization -file [file join $orb_build_dir board_routed_utilization.rpt]
report_timing_summary -file [file join $orb_build_dir board_routed_timing.rpt]
report_timing -delay_type max -max_paths 100 -nworst 1 -file [file join $orb_build_dir setup_paths.rpt]
report_timing -delay_type min -max_paths 20 -nworst 1 -file [file join $orb_build_dir hold_paths.rpt]
report_bus_skew -file [file join $orb_build_dir board_bus_skew.rpt]
report_drc -file [file join $orb_build_dir board_drc.rpt]
set setup_path [get_timing_paths -delay_type max -max_paths 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup_path] == 0 || [get_property SLACK $setup_path] < 0 ||
    ([llength $hold_path] != 0 && [get_property SLACK $hold_path] < 0)} {
    error "Timing does not close; bitstream generation is blocked until corrected. Reports: $orb_build_dir"
}
set bitfile [file join $orb_build_dir orb_board.bit]
write_bitstream $bitfile
puts "ORB_BITSTREAM_COMPLETE: $bitfile"
close_project
