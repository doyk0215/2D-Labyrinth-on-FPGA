# Story 9.5: timer arithmetic, protection, deadline priority and real top wiring.
set repo [file normalize [file join [file dirname [info script]] ..]]
set run_dir [file join $::env(TEMP) story95_buffs_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl [file join $repo rtl]
if {[catch {exec xvhdl -work work [file join $rtl Ps2Interface.vhd] [file join $rtl Mouse_Control.vhd] 2>@1} output]} {
    puts $output; error "VHDL compilation failed"
}
set cmd [list xvlog -work work -i $rtl]
foreach source [glob [file join $rtl *.v]] { lappend cmd $source }
foreach bench {tb_time_bonus tb_story95_items tb_top_story95_buffs tb_game_timer tb_item_ctrl tb_top_story92_items tb_top_story82_countdown} {
    lappend cmd [file join $repo tb ${bench}.v]
}
if {[catch {exec {*}$cmd 2>@1} output]} { puts $output; error "Verilog compilation failed" }
foreach {bench marker} {
    tb_time_bonus "PASS: time bonus"
    tb_story95_items "PASS: Story 9.5 items"
    tb_top_story95_buffs "PASS: Story 9.5 top"
    tb_game_timer "PASS: game_timer"
    tb_item_ctrl "PASS: item_ctrl"
    tb_top_story92_items "PASS: Story 9.2 MEDIUM generated-box pickup"
    tb_top_story82_countdown "PASS: Story 8.2 top countdown"
} {
    if {[catch {exec xelab -debug typical -L unisims_ver -top $bench -snapshot ${bench}_snapshot 2>@1} output]} {
        puts $output; error "Elaboration failed for $bench"
    }
    if {[catch {exec xsim ${bench}_snapshot -runall 2>@1} output]} { puts $output; error "Simulation failed for $bench" }
    puts $output
    if {[string first "FAIL" $output] >= 0 || [string first $marker $output] < 0} { error "$bench did not pass" }
}
puts "PASS Story 9.5 focused regression"
