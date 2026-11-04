# Focused Vivado regression for Story 3.3 after the generated menu background update.
set repo [file normalize [file join [file dirname [info script]] ..]]
set run_dir [file join $::env(TEMP) story33_control_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl [file join $repo rtl]
if {[catch {exec xvhdl -work work [file join $rtl Ps2Interface.vhd] [file join $rtl Mouse_Control.vhd] 2>@1} output]} {
    puts $output
    error "VHDL compilation failed"
}
set compile_cmd [list xvlog -work work -i $rtl]
foreach source [glob [file join $rtl *.v]] { lappend compile_cmd $source }
lappend compile_cmd [file join $repo tb tb_top_story33_control.v]
if {[catch {exec {*}$compile_cmd 2>@1} output]} {
    puts $output
    error "Verilog compilation failed"
}
puts $output
if {[catch {exec xelab -debug typical -L unisims_ver -top tb_top_story33_control -snapshot story33_control_snapshot 2>@1} output]} {
    puts $output
    error "Elaboration failed"
}
puts $output
if {[catch {exec xsim story33_control_snapshot -runall 2>@1} output]} {
    puts $output
    error "Simulation failed"
}
puts $output
if {[string first "FAIL" $output] >= 0 || [string first "PASS: Story 3.3" $output] < 0} {
    error "Story 3.3 control regression did not pass"
}
puts "PASS: Story 3.3 control compatibility"
exit
