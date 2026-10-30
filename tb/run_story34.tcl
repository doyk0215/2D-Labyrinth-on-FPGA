# Run the focused Story 3.4 reset and physics frame-budget benches with Vivado Simulator 2025.2.
set script_path [info script]
if {[file pathtype $script_path] ne "absolute"} {
    set script_path [file join [pwd] $script_path]
}
set repo_root [file dirname [file dirname [file normalize $script_path]]]
set run_dir [file join $::env(TEMP) story34_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl_dir [file join $repo_root rtl]
set tb_dir [file join $repo_root tb]

set vhdl_compile_cmd [list xvhdl -work work \
    [file join $rtl_dir Ps2Interface.vhd] \
    [file join $rtl_dir Mouse_Control.vhd]]
if {[catch {exec {*}$vhdl_compile_cmd 2>@1} output]} {
    puts $output
    error "xvhdl compilation failed"
}
puts $output

set compile_cmd [list xvlog -work work -i $rtl_dir]
foreach source [glob [file join $rtl_dir *.v]] { lappend compile_cmd $source }
foreach bench {tb_game_ctrl tb_snap_rotation tb_top_story34_reset tb_story34_frame_budget} {
    lappend compile_cmd [file join $tb_dir ${bench}.v]
}
if {[catch {exec {*}$compile_cmd 2>@1} output]} {
    puts $output
    error "xvlog compilation failed"
}
puts $output

foreach {bench snapshot marker} {
    tb_game_ctrl game_ctrl_story34_snapshot "PASS: game_ctrl"
    tb_snap_rotation snap_rotation_story34_snapshot "PASS: snap rotation"
    tb_top_story34_reset top_story34_reset_snapshot "PASS: Story 3.4 reset"
    tb_story34_frame_budget story34_frame_budget_snapshot "PASS: Story 3.4 physics frame budget"
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

puts "PASS: focused Story 3.4 controller reset priority, integration, and frame-budget benches"
