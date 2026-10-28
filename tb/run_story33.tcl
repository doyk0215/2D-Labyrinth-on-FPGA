# Run Story 3.3 goal/control benches together with PR #47's visual benches.
# Vivado 2025.2: vivado -mode batch -source <repo>/tb/run_story33.tcl
set script_path [info script]
if {[file pathtype $script_path] ne "absolute"} {
    set script_path [file join [pwd] $script_path]
}
set repo_root [file dirname [file dirname [file normalize $script_path]]]
set run_dir [file join $::env(TEMP) story33_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl_dir [file join $repo_root rtl]
set tb_dir [file join $repo_root tb]

if {[catch {exec xvhdl -work work \
    [file join $rtl_dir Ps2Interface.vhd] \
    [file join $rtl_dir Mouse_Control.vhd] 2>@1} output]} {
    puts $output
    error "xvhdl compilation failed"
}
puts $output

set compile_cmd [list xvlog -work work -i $rtl_dir]
foreach source [glob [file join $rtl_dir *.v]] { lappend compile_cmd $source }
foreach bench {tb_goal_detection tb_game_ctrl tb_top_story33_control tb_win_render tb_top_win_indication} {
    lappend compile_cmd [file join $tb_dir ${bench}.v]
}
if {[catch {exec {*}$compile_cmd 2>@1} output]} {
    puts $output
    error "xvlog compilation failed"
}
puts $output

foreach {bench snapshot marker} {
    tb_goal_detection goal_detection_snapshot "PASS: goal detection"
    tb_game_ctrl game_ctrl_snapshot "PASS: game_ctrl startup"
    tb_top_story33_control top_story33_control_snapshot "PASS: Story 3.3 goal detector"
    tb_win_render win_render_snapshot "PASS: win render"
    tb_top_win_indication top_win_snapshot "PASS: top win indication"
} {
    if {[catch {exec xelab -debug typical -L unisims_ver -top $bench -snapshot $snapshot 2>@1} output]} {
        puts $output
        error "elaboration failed for $bench"
    }
    puts $output
    if {[catch {exec xsim $snapshot -runall 2>@1} output]} {
        puts $output
        error "simulation failed for $bench"
    }
    puts $output
    if {[string first "FAIL" $output] >= 0 || [string first $marker $output] < 0} {
        error "$bench did not pass"
    }
}
puts "PASS: Story 3.3 goal/control and PR #47 visual benches"
