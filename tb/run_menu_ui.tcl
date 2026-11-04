# Focused Vivado regression for the monitor menu text and background lifecycle.
set script_path [info script]
if {[file pathtype $script_path] ne "absolute"} {
    set script_path [file join [pwd] $script_path]
}
set repo_root [file dirname [file dirname $script_path]]
set rtl_dir [file join $repo_root rtl]
set tb_dir [file join $repo_root tb]
set stamp [clock format [clock seconds] -format "%Y%m%d-%H%M%S"]
set run_dir [file join $::env(TEMP) "menu_ui_vivado_$stamp"]
file mkdir $run_dir
cd $run_dir

set vhdl_cmd [list xvhdl -work work \
    [file join $rtl_dir Ps2Interface.vhd] \
    [file join $rtl_dir Mouse_Control.vhd]]
if {[catch {exec {*}$vhdl_cmd 2>@1} output]} {
    puts $output
    error "VHDL compilation failed"
}
puts $output

set compile_cmd [list xvlog -work work -i $rtl_dir]
foreach source [glob [file join $rtl_dir *.v]] { lappend compile_cmd $source }
lappend compile_cmd [file join $tb_dir tb_monitor_menu_overlay.v]
lappend compile_cmd [file join $tb_dir tb_menu_background.v]
if {[catch {exec {*}$compile_cmd 2>@1} output]} {
    puts $output
    error "menu UI Verilog compilation failed"
}
puts $output

foreach {top snapshot marker} {
    tb_monitor_menu_overlay menu_overlay_snapshot "PASS: Welcome page renders U/D = SELECT STAGE"
    tb_menu_background menu_background_snapshot "PASS: centered N=20 menu maze receives a fresh seed"
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
        error "$top did not pass its expected checks"
    }
}
puts "PASS: monitor menu UI regression"
