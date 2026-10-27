# Run the current HDL regression, including Story 4.2 and both OLED
# colour-pattern and text-frame simulations, under Vivado 2025.2.
# With -oled-only, run just the two OLED simulations.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
if {[lsearch -exact $argv -oled-only] < 0} {
    source [file join $repo_root tb run_current_stories.tcl]
    puts "PASS Story 4.2 Vivado regression and both OLED display modes"
} else {
    source [file join $repo_root tb run_oled_display.tcl]
}
