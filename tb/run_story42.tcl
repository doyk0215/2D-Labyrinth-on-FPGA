# Run the current HDL regression, including Story 4.2, followed by both OLED
# colour-pattern and text-frame simulations under Vivado 2025.2.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set run_dir [file join $::env(TEMP) current_stories_vivado_run]
if {[lsearch -exact $argv -oled-only] < 0} {
    source [file join $repo_root tb run_current_stories.tcl]
} else {
    file mkdir $run_dir
}
cd $run_dir

set vivado_root [file dirname [file normalize [info nameofexecutable]]]
while {![file exists [file join $vivado_root data verilog src glbl.v]] &&
       [file dirname $vivado_root] ne $vivado_root} {
    set vivado_root [file dirname $vivado_root]
}
set glbl_source [file join $vivado_root data verilog src glbl.v]
if {![file exists $glbl_source]} {
    error "Could not locate Vivado data/verilog/src/glbl.v"
}
if {[catch {exec xvlog -work work -i [file join $repo_root rtl] \
    [file join $repo_root tb tb_oled_display.v] 2>@1} output]} {
    puts $output
    error "OLED testbench compilation failed"
}
if {[catch {exec xvlog -work work $glbl_source 2>@1} output]} {
    puts $output
    error "Vivado glbl compilation failed"
}

foreach text_mode {0 1} {
    set snapshot oled_mode_${text_mode}_snapshot
    set mode_name [expr {$text_mode ? "text" : "colour pattern"}]
    puts "Elaborating OLED $mode_name regression..."
    if {[catch {exec xelab -debug typical -L unisims_ver \
        -top tb_oled_display_with_glbl -snapshot $snapshot \
        -generic_top "TEXT=$text_mode" 2>@1} output]} {
        puts $output
        error "OLED $mode_name xelab failed"
    }
    puts $output

    if {[catch {exec xsim $snapshot -runall 2>@1} output]} {
        puts $output
        error "OLED $mode_name xsim failed"
    }
    puts $output
    if {[string first "FAIL" $output] >= 0 ||
        [string first "PASS: Oled_Display on 6.25 MHz" $output] < 0} {
        error "OLED $mode_name regression did not pass"
    }
}

puts "PASS Story 4.2 Vivado regression and both OLED display modes"
