# Build the Basys 3 bitstream from the generated Vivado project.
# Usage from the repository root:
#   vivado -mode batch -source scripts/build_bitstream.tcl

set repo [file normalize [file join [file dirname [info script]] ..]]
set project [file join $repo vivado labyrinth.xpr]

open_project $project
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

puts "Bitstream: [file join $repo vivado labyrinth.runs impl_1 My_Top_Module.bit]"
