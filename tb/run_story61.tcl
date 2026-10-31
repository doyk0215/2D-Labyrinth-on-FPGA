# Story 6.1: exercise shared state encodings and the actual top-level ports.
# Vivado 2025.2: source this script using its absolute path.
set repo [file normalize [file join [file dirname [info script]] ..]]
set run_dir [file join $::env(TEMP) story61_state_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl [file join $repo rtl]
if {[catch {exec xvhdl -work work [file join $rtl Ps2Interface.vhd] [file join $rtl Mouse_Control.vhd] 2>@1} output]} {
    puts $output; error "VHDL compilation failed"
}
set cmd [list xvlog -work work -i $rtl]
foreach source [glob [file join $rtl *.v]] { lappend cmd $source }
lappend cmd [file join $repo tb tb_game_state_encoding.v]
if {[catch {exec {*}$cmd 2>@1} output]} { puts $output; error "Verilog compilation failed" }
if {[catch {exec xelab -debug typical -L unisims_ver -top tb_game_state_encoding -snapshot shared_state_snapshot 2>@1} output]} {
    puts $output; error "Shared state elaboration failed"
}
if {[catch {exec xsim shared_state_snapshot -runall 2>@1} output]} { puts $output; error "Shared state simulation failed" }
puts $output
if {[string first "FAIL" $output] >= 0 || [string first "PASS: shared game state" $output] < 0} {
    error "Shared state regression did not pass"
}
