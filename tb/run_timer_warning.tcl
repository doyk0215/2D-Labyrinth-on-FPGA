# Focused Vivado regression for the late-game VGA warning effect.
set script_path [info script]
if {[file pathtype $script_path] ne "absolute"} {
    set script_path [file join [pwd] $script_path]
}
set repo_root [file dirname [file dirname $script_path]]
set rtl_dir [file join $repo_root rtl]
set tb_dir [file join $repo_root tb]
set run_dir [file join $::env(TEMP) timer_warning_vivado_run]
file mkdir $run_dir
cd $run_dir

set compile_cmd [list xvlog -work work -i $rtl_dir]
foreach source [glob [file join $rtl_dir *.v]] { lappend compile_cmd $source }
lappend compile_cmd [file join $tb_dir tb_timer_warning_overlay.v]
if {[catch {exec {*}$compile_cmd 2>@1} output]} {
    puts $output
    error "Timer-warning Verilog compilation failed"
}
puts $output

if {[catch {exec xelab -debug typical -L unisims_ver -top tb_timer_warning_overlay -snapshot timer_warning_snapshot 2>@1} output]} {
    puts $output
    error "Timer-warning elaboration failed"
}
puts $output
if {[catch {exec xsim timer_warning_snapshot -runall 2>@1} output]} {
    puts $output
    error "Timer-warning simulation failed"
}
puts $output
if {[string first "FAIL" $output] >= 0 ||
    [string first "PASS: timer warning threshold, pulse, ramp, and HUD flash" $output] < 0} {
    error "Timer-warning regression did not report PASS"
}
puts "PASS: timer warning regression"
exit
