# Story 9.4 fog of war and invert controls, plus the benches it touches.
set repo [file normalize [file join [file dirname [info script]] ..]]
set run_dir [file join $::env(TEMP) story94_effects_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl [file join $repo rtl]
if {[catch {exec xvhdl -work work [file join $rtl Ps2Interface.vhd] [file join $rtl Mouse_Control.vhd] 2>@1} output]} {
    puts $output; error "VHDL compilation failed"
}
set cmd [list xvlog -work work -i $rtl -i [file join $repo tb]]
foreach source [glob [file join $rtl *.v]] { lappend cmd $source }
foreach bench {tb_fog_render tb_top_story94_invert tb_ball_overlay tb_rotated_render tb_switch_mapping tb_oled_status_text} { lappend cmd [file join $repo tb ${bench}.v] }
if {[catch {exec {*}$cmd 2>@1} output]} { puts $output; error "Verilog compilation failed" }
foreach {bench marker} {tb_fog_render "PASS: fog render" tb_top_story94_invert "PASS: Story 9.4 invert" tb_ball_overlay "PASS: ball_overlay" tb_rotated_render "PASS: rotated renderer" tb_switch_mapping "PASS: switch mapping" tb_oled_status_text "PASS: OLED status formatter"} {
    if {[catch {exec xelab -debug typical -L unisims_ver -top $bench -snapshot ${bench}_snapshot 2>@1} output]} {
        puts $output; error "Elaboration failed for $bench"
    }
    if {[catch {exec xsim ${bench}_snapshot -runall 2>@1} output]} { puts $output; error "Simulation failed for $bench" }
    puts $output
    if {[string first "FAIL" $output] >= 0 || [string first $marker $output] < 0} { error "$bench did not pass" }
}
puts "PASS Story 9.4 focused regression"
