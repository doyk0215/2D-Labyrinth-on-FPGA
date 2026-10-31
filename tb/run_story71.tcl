# Focused Story 7.1 Vivado 2025.2 coverage for stage-sized maps through N=15.
set script_path [info script]
if {[file pathtype $script_path] ne "absolute"} {
    set script_path [file join [pwd] $script_path]
}
set repo_root [file dirname [file dirname [file normalize $script_path]]]
set run_dir [file join $::env(TEMP) story71_vivado_run]
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
foreach bench {tb_maze_gen tb_ball_physics tb_goal_detection tb_story71_map tb_story71_physics} {
    lappend compile_cmd [file join $tb_dir ${bench}.v]
}
if {[catch {exec {*}$compile_cmd 2>@1} output]} {
    puts $output
    error "xvlog compilation failed"
}
puts $output

foreach {bench snapshot marker} {
    tb_goal_detection story71_goal_snapshot "PASS: goal detection"
    tb_maze_gen story71_maze_gen_snapshot "PASS: maze_gen"
    tb_ball_physics story71_legacy_physics_snapshot "PASS: ball_physics"
    tb_story71_map story71_map_snapshot "PASS: Story 7.1 renderer"
    tb_story71_physics story71_physics_snapshot "PASS: Story 7.1 N=15 physics"
} {
    if {[catch {exec xelab -debug typical -L unisims_ver -top $bench -snapshot $snapshot 2>@1} output]} {
        puts $output
        error "xelab failed for $bench"
    }
    puts $output
    if {[catch {exec xsim $snapshot -runall 2>@1} output]} {
        puts $output
        error "xsim failed for $bench"
    }
    puts $output
    if {[string first "FAIL" $output] >= 0 || [string first $marker $output] < 0} {
        error "$bench did not pass"
    }
}
puts "PASS: Story 7.1 stage-sized map, generator and physics benches"
