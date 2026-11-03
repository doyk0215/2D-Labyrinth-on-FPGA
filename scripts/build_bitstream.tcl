# Build the Basys 3 bitstream from the current RTL sources in a fresh,
# isolated project under build/, leaving the shared vivado/ project untouched.
# Usage from the repository root:
#   vivado -mode batch -source scripts/build_bitstream.tcl
set repo [file normalize [file join [file dirname [info script]] ..]]
set build_stamp [clock format [clock seconds] -format "%Y%m%d-%H%M%S"]
set project_dir [file join $repo build "sevenseg-vga-status-vivado-$build_stamp"]

create_project -force labyrinth $project_dir -part xc7a35tcpg236-1

set rtl_files [glob -nocomplain [file join $repo rtl *.v]]
if {[llength $rtl_files] > 0} { add_files -norecurse $rtl_files }
set vhdl_files [glob -nocomplain [file join $repo rtl *.vhd]]
if {[llength $vhdl_files] > 0} { add_files -norecurse $vhdl_files }
set hdr [file join $repo rtl labyrinth_pkg.vh]
add_files -norecurse $hdr
set_property file_type {Verilog Header} [get_files $hdr]
set_property include_dirs [list [file join $repo rtl]] [get_filesets sources_1]
set_property target_language Verilog [current_project]
set_property top My_Top_Module [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $repo constraints basys3.xdc]

launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $synth_status"
if {[string first "Complete" $synth_status] < 0} {
    error "Synthesis did not complete successfully"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $impl_status"
if {[string first "Complete" $impl_status] < 0} {
    error "Implementation/bitstream generation did not complete successfully"
}

puts "Bitstream: [file join $project_dir labyrinth.runs impl_1 My_Top_Module.bit]"
