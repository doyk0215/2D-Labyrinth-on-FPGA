# Approved brick-wall texture plus existing rendering/overlay regression.
# Full frames are captured as PPMs in TEMP/story101a_brick_vivado_run.
set repo [file normalize [file join [file dirname [info script]] ..]]
set run_dir [file join $::env(TEMP) story101a_brick_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl [file join $repo rtl]
set tb [file join $repo tb]
if {[catch {exec xvhdl -work work [file join $rtl Ps2Interface.vhd] [file join $rtl Mouse_Control.vhd] 2>@1} output]} {
    puts $output; error "VHDL compilation failed"
}
set cmd [list xvlog -work work -i $rtl -i $tb]
foreach source [glob [file join $rtl *.v]] { lappend cmd $source }
set benches {tb_brick_wall_pixel tb_render tb_rotated_render tb_story73_render tb_n20_render tb_story71_map tb_fog_render tb_win_render tb_lose_render}
foreach bench $benches { lappend cmd [file join $tb ${bench}.v] }
if {[catch {exec {*}$cmd 2>@1} output]} { puts $output; error "Verilog compilation failed" }
foreach {bench marker} {
    tb_brick_wall_pixel "PASS: brick texture"
    tb_render "PASS: generated maze"
    tb_rotated_render "PASS: rotated renderer"
    tb_story73_render "PASS: Story 7.3 N=15 render"
    tb_n20_render "PASS: N=20 render"
    tb_story71_map "PASS: Story 7.1 renderer"
    tb_fog_render "PASS: fog render"
    tb_win_render "PASS: win render"
    tb_lose_render "PASS: lose render"
} {
    puts "Running $bench..."
    set elab [list xelab -debug typical -L unisims_ver -top $bench -snapshot ${bench}_snapshot]
    if {$bench eq "tb_rotated_render"} { lappend elab -generic_top CAPTURE_FRAMES=1 }
    if {[catch {exec {*}$elab 2>@1} output]} { puts $output; error "Elaboration failed for $bench" }
    if {[catch {exec xsim ${bench}_snapshot -runall 2>@1} output]} { puts $output; error "Simulation failed for $bench" }
    puts $output
    if {[string first "FAIL" $output] >= 0 || [string first $marker $output] < 0} { error "$bench did not pass" }
}
puts "PASS Story 10.1a brick wall focused regression (9 benches)"
