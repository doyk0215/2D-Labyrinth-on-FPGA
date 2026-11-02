# Story 8.2 countdown and real-top timeout/replay/reset checks.
set repo [file normalize [file join [file dirname [info script]] ..]]
set run_dir [file join $::env(TEMP) story82_countdown_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl [file join $repo rtl]
if {[catch {exec xvhdl -work work [file join $rtl Ps2Interface.vhd] [file join $rtl Mouse_Control.vhd] 2>@1} output]} {
    puts $output; error "VHDL compilation failed"
}
set cmd [list xvlog -work work -i $rtl]
foreach source [glob [file join $rtl *.v]] { lappend cmd $source }
foreach bench {tb_game_timer tb_top_story82_countdown tb_game_state_encoding} {
    lappend cmd [file join $repo tb ${bench}.v]
}
if {[catch {exec {*}$cmd 2>@1} output]} { puts $output; error "Verilog compilation failed" }
foreach {bench marker} {
    tb_game_timer "PASS: game_timer"
    tb_top_story82_countdown "PASS: Story 8.2 top countdown"
    tb_game_state_encoding "PASS: shared game state"
} {
    if {[catch {exec xelab -debug typical -L unisims_ver -top $bench -snapshot ${bench}_snapshot 2>@1} output]} {
        puts $output; error "Elaboration failed for $bench"
    }
    if {[catch {exec xsim ${bench}_snapshot -runall 2>@1} output]} { puts $output; error "Simulation failed for $bench" }
    puts $output
    if {[string first "FAIL" $output] >= 0 || [string first $marker $output] < 0} { error "$bench did not pass" }
}
puts "PASS Story 8.2 focused regression"
