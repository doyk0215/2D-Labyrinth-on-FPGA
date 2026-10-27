# Run Story 1.4 controller and top-level integration benches with Vivado 2025.2.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set rtl_dir [file join $repo_root rtl]
set run_dir [file join $::env(TEMP) story14_vivado_run]
file mkdir $run_dir
cd $run_dir

set vhdl_sources [list \
    [file join $rtl_dir Ps2Interface.vhd] \
    [file join $rtl_dir Mouse_Control.vhd]]
set vhdl_cmd [list xvhdl -work work]
foreach source $vhdl_sources { lappend vhdl_cmd $source }
if {[catch {exec {*}$vhdl_cmd 2>@1} output]} {
    puts $output
    error "xvhdl compilation failed"
}
puts $output

set compile_cmd [list xvlog -work work -i $rtl_dir]
foreach source [glob [file join $rtl_dir *.v]] { lappend compile_cmd $source }
foreach source [glob [file join $repo_root tb *.v]] { lappend compile_cmd $source }
if {[catch {exec {*}$compile_cmd 2>@1} output]} {
    puts $output
    error "xvlog compilation failed"
}
puts $output

foreach {top snapshot marker} {
    tb_maze_gen maze_gen_snapshot "PASS: maze_gen - all mazes perfect"
    tb_game_ctrl game_ctrl_snapshot "PASS: game_ctrl"
    tb_top_story14_integration top_story14_snapshot "PASS: Story 1.4 top"
} {
    if {[catch {exec xelab -debug typical -L unisims_ver -top $top -snapshot $snapshot 2>@1} output]} {
        puts $output
        error "xelab failed for $top"
    }
    puts $output
    if {[catch {exec xsim $snapshot -runall 2>@1} output]} {
        puts $output
        error "xsim failed for $top"
    }
    puts $output
    if {[string first "FAIL" $output] >= 0 || [string first $marker $output] < 0} {
        error "$top did not pass"
    }
}

puts "PASS Story 1.4 Vivado regression"
