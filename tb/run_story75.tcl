# Focused Story 7.5 generator regression (Vivado Simulator 2025.2).
# Runs the many-seed maze_gen bench with loop-cap and connectivity checks.
set script_path [info script]
if {[file pathtype $script_path] ne "absolute"} {
    set script_path [file join [pwd] $script_path]
}
set repo_root [file dirname [file dirname [file normalize $script_path]]]
set run_dir [file join $::env(TEMP) story75_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl_dir [file join $repo_root rtl]
set tb_dir [file join $repo_root tb]

set compile_cmd [list xvlog -work work -i $rtl_dir \
    [file join $rtl_dir maze_gen.v] \
    [file join $rtl_dir seed_source.v] \
    [file join $tb_dir tb_maze_gen.v]]
if {[catch {exec {*}$compile_cmd 2>@1} output]} {
    puts $output
    error "Story 7.5 xvlog compilation failed"
}
puts $output

if {[catch {exec xelab -debug typical -L unisims_ver -top tb_maze_gen \
    -snapshot story75_maze_gen_snapshot 2>@1} output]} {
    puts $output
    error "Story 7.5 xelab failed"
}
puts $output

if {[catch {exec xsim story75_maze_gen_snapshot -runall 2>@1} output]} {
    puts $output
    error "Story 7.5 xsim failed"
}
puts $output
if {[string first "FAIL" $output] >= 0 ||
    [string first "PASS: maze_gen - EASY perfect, HARD/N=15 loop counts within caps" $output] < 0} {
    error "Story 7.5 generator regression did not pass"
}
puts "PASS: Story 7.5 focused generator regression"
