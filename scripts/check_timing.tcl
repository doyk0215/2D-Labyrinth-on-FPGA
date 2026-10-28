# Synthesize and route the Basys 3 design, then write timing/utilization
# reports. This intentionally stops at route_design and does not create a
# bitstream. The temporary project is kept under the operating-system TEMP.
# Usage from the repository root:
#   vivado -mode batch -source scripts/check_timing.tcl

set script_path [info script]
if {[file pathtype $script_path] ne "absolute"} {
    set script_path [file join [pwd] $script_path]
}
set repo_root [file normalize [file join [file dirname $script_path] ..]]
set project_dir [file join $::env(TEMP) "labyrinth_timing_[clock seconds]"]
set rtl_dir [file join $repo_root rtl]

create_project labyrinth_timing $project_dir -part xc7a35tcpg236-1

set verilog_files [glob -nocomplain [file join $rtl_dir *.v]]
if {[llength $verilog_files] > 0} { add_files -norecurse $verilog_files }
set vhdl_files [glob -nocomplain [file join $rtl_dir *.vhd]]
if {[llength $vhdl_files] > 0} { add_files -norecurse $vhdl_files }
set header_file [file join $rtl_dir labyrinth_pkg.vh]
add_files -norecurse $header_file
set_property file_type {Verilog Header} [get_files $header_file]
set_property include_dirs [list $rtl_dir] [get_filesets sources_1]
set_property target_language Verilog [current_project]
set_property top My_Top_Module [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $repo_root constraints basys3.xdc]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $synth_status"
if {[string first "Complete" $synth_status] < 0} {
    error "Synthesis did not complete successfully"
}

launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status (through route_design): $impl_status"
if {[string first "Complete" $impl_status] < 0} {
    error "Implementation did not complete through route_design"
}

open_run impl_1
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $project_dir routed_timing_summary.rpt]
report_utilization -file [file join $project_dir routed_utilization.rpt]
report_drc -file [file join $project_dir routed_drc.rpt]
puts "Timing report: [file join $project_dir routed_timing_summary.rpt]"
puts "Utilization report: [file join $project_dir routed_utilization.rpt]"
puts "DRC report: [file join $project_dir routed_drc.rpt]"
puts "Bitstream generation skipped."
