# Story 6.2 button classification and full reset with the actual peripherals.
set repo [file normalize [file join [file dirname [info script]] ..]]
set run_dir [file join $::env(TEMP) story62_reset_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl [file join $repo rtl]
if {[catch {exec xvhdl -work work [file join $rtl Ps2Interface.vhd] [file join $rtl Mouse_Control.vhd] 2>@1} output]} {
    puts $output; error "VHDL compilation failed"
}
set cmd [list xvlog -work work -i $rtl]
foreach source [glob [file join $rtl *.v]] { lappend cmd $source }
foreach bench {tb_centre_button tb_top_story62_reset} { lappend cmd [file join $repo tb ${bench}.v] }
if {[catch {exec {*}$cmd 2>@1} output]} { puts $output; error "Verilog compilation failed" }
foreach {bench marker} {tb_centre_button "PASS: centre button" tb_top_story62_reset "PASS: Story 6.2 long reset"} {
    if {[catch {exec xelab -debug typical -L unisims_ver -top $bench -snapshot ${bench}_snapshot 2>@1} output]} {
        puts $output; error "Elaboration failed for $bench"
    }
    if {[catch {exec xsim ${bench}_snapshot -runall 2>@1} output]} { puts $output; error "Simulation failed for $bench" }
    puts $output
    if {[string first "FAIL" $output] >= 0 || [string first $marker $output] < 0} { error "$bench did not pass" }
}
puts "PASS Story 6.2 focused regression"
