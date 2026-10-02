# Inspect a completed implementation checkpoint without modifying its project.
if {[llength $argv] != 2} { error "Pass checkpoint and output directory" }
open_checkpoint [lindex $argv 0]
set report_dir [lindex $argv 1]
report_timing -delay_type max -max_paths 100 -nworst 1 -file [file join $report_dir setup_paths.rpt]
report_timing -delay_type min -max_paths 20 -nworst 1 -file [file join $report_dir hold_paths.rpt]
report_timing_summary -report_unconstrained -file [file join $report_dir timing_summary.rpt]
report_clock_interaction -file [file join $report_dir clock_interaction.rpt]
close_design
