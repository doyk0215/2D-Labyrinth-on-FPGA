set repo [file normalize [file join [file dirname [info script]] ..]]
set run_dir [file join $::env(TEMP) story101b_menu_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl [file join $repo rtl]
set tb [file join $repo tb]
if {[catch {exec xvhdl -work work [file join $rtl Ps2Interface.vhd] [file join $rtl Mouse_Control.vhd] 2>@1} out]} { puts $out;error "VHDL compile failed" }
set cmd [list xvlog -work work -i $rtl -i $tb]
foreach source [glob [file join $rtl *.v]] {lappend cmd $source}
foreach bench {tb_welcome_menu_overlay tb_render_palette tb_monitor_menu_overlay tb_menu_ctrl tb_oled_status_text tb_render tb_rotated_render tb_story73_render tb_n20_render tb_fog_render tb_win_render tb_lose_render tb_top_story42_integration tb_top_story43_integration tb_top_win_indication} {lappend cmd [file join $tb ${bench}.v]}
if {[catch {exec {*}$cmd 2>@1} out]} {puts $out;error "Verilog compile failed"}
foreach {bench marker} {
    tb_welcome_menu_overlay "PASS: welcome menu"
    tb_render_palette "PASS: gray walls"
    tb_monitor_menu_overlay "PASS: Welcome page"
    tb_menu_ctrl "PASS: menu_ctrl"
    tb_oled_status_text "PASS: OLED status formatter"
    tb_render "PASS: generated maze"
    tb_rotated_render "PASS: rotated renderer"
    tb_story73_render "PASS: Story 7.3 N=15 render"
    tb_n20_render "PASS: N=20 render"
    tb_fog_render "PASS: fog render"
    tb_win_render "PASS: win render"
    tb_lose_render "PASS: lose render"
    tb_top_story42_integration "PASS: Story 4.2 top"
    tb_top_story43_integration "PASS: Story 4.3 top"
    tb_top_win_indication "PASS: top win indication"
} {
    puts "Running $bench..."
    if {[catch {exec xelab -debug typical -L unisims_ver -top $bench -snapshot ${bench}_snapshot 2>@1} out]} {puts $out;error "Elaboration failed: $bench"}
    if {[catch {exec xsim ${bench}_snapshot -runall 2>@1} out]} {puts $out;error "Simulation failed: $bench"}
    puts $out
    if {[string first "FAIL" $out]>=0 || [string first $marker $out]<0} {error "$bench did not pass"}
}
puts "PASS Story 10.1b menu/palette regression (15 benches)"
