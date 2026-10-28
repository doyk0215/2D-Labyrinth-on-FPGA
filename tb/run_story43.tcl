# Run the full current-stories regression, including Story 4.3 and both OLED
# colour-pattern and text-frame simulations, under Vivado 2025.2.
set script_path [info script]
if {[file pathtype $script_path] ne "absolute"} {
    set script_path [file join [pwd] $script_path]
}
set repo_root [file dirname [file dirname $script_path]]
source [file join $repo_root tb run_current_stories.tcl]
puts "PASS Story 4.3 Vivado regression and both OLED display modes"
