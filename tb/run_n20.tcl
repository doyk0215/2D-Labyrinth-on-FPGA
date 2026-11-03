set repo [file normalize [file join [file dirname [info script]] ..]]
set run_dir [file join $::env(TEMP) n20_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl [file join $repo rtl]
set tb [file join $repo tb]
foreach data_file [glob [file join $tb data *.mem]] { file copy -force $data_file $run_dir }
if {[catch {exec xvhdl -work work [file join $rtl Ps2Interface.vhd] [file join $rtl Mouse_Control.vhd] 2>@1} output]} {
    puts $output; error "VHDL compilation failed"
}
set cmd [list xvlog -work work -i $rtl -i $tb]
foreach source [glob [file join $rtl *.v]] { lappend cmd $source }
foreach bench {tb_maze_gen_golden tb_n20_maze tb_n20_play tb_n20_render tb_top_n20 tb_custom_stage tb_menu_ctrl} {
    lappend cmd [file join $tb ${bench}.v]
}
if {[catch {exec {*}$cmd 2>@1} output]} { puts $output; error "Verilog compilation failed" }
foreach {bench marker} {
    tb_maze_gen_golden "PASS: maze_gen golden"
    tb_n20_maze "PASS: N=20 maze_gen"
    tb_n20_play "PASS: N=20 play"
    tb_n20_render "PASS: N=20 render"
    tb_top_n20 "PASS: N=20 top"
    tb_custom_stage "PASS: custom stage"
    tb_menu_ctrl "PASS: menu_ctrl"
} {
    if {[catch {exec xelab -debug typical -L unisims_ver -top $bench -snapshot ${bench}_snapshot 2>@1} output]} {
        puts $output; error "Elaboration failed for $bench"
    }
    if {[catch {exec xsim ${bench}_snapshot -runall 2>@1} output]} { puts $output; error "Simulation failed for $bench" }
    puts $output
    if {[string first "FAIL" $output] >= 0 || [string first $marker $output] < 0} { error "$bench did not pass" }
}
puts "PASS N=20 focused regression"
