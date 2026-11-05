# Buff-green instant time-bonus receipt and unchanged timer/item behavior.
set repo [file normalize [file join [file dirname [info script]] ..]]
set run [file join $::env(TEMP) time_pickup_hud_vivado_run]
file mkdir $run
cd $run
set rtl [file join $repo rtl]
set tb [file join $repo tb]
if {[catch {exec xvhdl -work work [file join $rtl Ps2Interface.vhd] [file join $rtl Mouse_Control.vhd] 2>@1} out]} {puts $out;error "VHDL compilation failed"}
set benches {tb_time_pickup_hud tb_top_time_pickup_hud tb_timer_warning_overlay tb_time_bonus tb_top_story95_buffs tb_game_timer tb_top_story82_countdown tb_item_roulette}
set cmd [list xvlog -work work -i $rtl]
foreach source [glob [file join $rtl *.v]] {lappend cmd $source}
foreach bench $benches {lappend cmd [file join $tb ${bench}.v]}
if {[catch {exec {*}$cmd 2>@1} out]} {puts $out;error "Verilog compilation failed"}
foreach bench $benches {
    puts "Running $bench..."
    if {[catch {exec xelab -debug typical -L unisims_ver -top $bench -snapshot ${bench}_snapshot 2>@1} out]} {puts $out;error "Elaboration failed: $bench"}
    if {[catch {exec xsim ${bench}_snapshot -runall 2>@1} out]} {puts $out;error "Simulation failed: $bench"}
    puts $out
    if {[string first "FAIL" $out]>=0 || [string first "PASS:" $out]<0} {error "$bench did not pass"}
}
puts "PASS time pickup HUD focused regression (8 benches)"
