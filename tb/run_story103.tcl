set repo [file normalize [file join [file dirname [info script]] ..]]
set run [file join $::env(TEMP) story103_instant_death_vivado_run]
file mkdir $run
cd $run
set rtl [file join $repo rtl]
set tb [file join $repo tb]
foreach data [glob [file join $tb data *.mem]] {file copy -force $data $run}
if {[catch {exec xvhdl -work work [file join $rtl Ps2Interface.vhd] [file join $rtl Mouse_Control.vhd] 2>@1} out]} {puts $out;error "VHDL compilation failed"}
set benches {tb_instant_death_item tb_instant_death_respawn tb_top_instant_death tb_item_icon_rom tb_oled_roulette_pixel tb_item_roulette tb_item_ctrl tb_item_durations tb_ball_physics tb_camera tb_item_gravity tb_story71_physics tb_n20_play tb_game_timer tb_time_bonus tb_game_ctrl tb_top_story82_countdown tb_top_story95_buffs}
if {[llength $argv]>0} {set benches $argv}
set cmd [list xvlog -work work -i $rtl -i $tb]
foreach source [glob [file join $rtl *.v]] {lappend cmd $source}
foreach bench $benches {lappend cmd [file join $tb ${bench}.v]}
if {[catch {exec {*}$cmd 2>@1} out]} {puts $out;error "Verilog compilation failed"}
foreach bench $benches {
    puts "Running $bench..."
    if {[catch {exec xelab -debug typical -L unisims_ver -top $bench -snapshot ${bench}_snapshot 2>@1} out]} {puts $out;error "Elaboration failed: $bench"}
    if {[catch {exec xsim ${bench}_snapshot -runall 2>@1} out]} {puts $out;error "Simulation failed: $bench"}
    puts $out
    if {[string first "FAIL" $out]>=0 || [string first "PASS" $out]<0} {error "$bench did not pass"}
}
puts "PASS Story 10.3 focused regression ([llength $benches] benches)"
