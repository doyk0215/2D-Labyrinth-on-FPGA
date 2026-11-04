# Focused Vivado regression for the maze generator, including stage box counts.
set repo [file normalize [file join [file dirname [info script]] ..]]
set run_dir [file join $::env(TEMP) maze_gen_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl [file join $repo rtl]
set tb [file join $repo tb]
set compile_cmd [list xvlog -work work -i $rtl \
    [file join $rtl maze_gen.v] [file join $rtl seed_source.v] \
    [file join $tb tb_maze_gen.v]]
if {[catch {exec {*}$compile_cmd 2>@1} output]} {
    puts $output
    error "Maze generator compilation failed"
}
puts $output
if {[catch {exec xelab -debug typical -L unisims_ver -top tb_maze_gen -snapshot maze_gen_snapshot 2>@1} output]} {
    puts $output
    error "Maze generator elaboration failed"
}
puts $output
if {[catch {exec xsim maze_gen_snapshot -runall 2>@1} output]} {
    puts $output
    error "Maze generator simulation failed"
}
puts $output
if {[string first "FAIL" $output] >= 0 || [string first "PASS: maze_gen" $output] < 0} {
    error "Maze generator regression did not pass"
}
puts "PASS: maze generator regression"
exit
