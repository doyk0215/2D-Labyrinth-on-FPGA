# Run the focused Story 4.4 timer and OLED status tests with Vivado Simulator 2025.2.
set script_path [info script]
if {[file pathtype $script_path] ne "absolute"} {
    set script_path [file join [pwd] $script_path]
}
set repo_root [file dirname [file dirname [file normalize $script_path]]]
set run_dir [file join $::env(TEMP) story44_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl_dir [file join $repo_root rtl]
set tb_dir [file join $repo_root tb]

set vhdl_compile_cmd [list xvhdl -work work \
    [file join $rtl_dir Ps2Interface.vhd] \
    [file join $rtl_dir Mouse_Control.vhd]]
if {[catch {exec {*}$vhdl_compile_cmd 2>@1} output]} {
    puts $output
    error "xvhdl compilation failed"
}
puts $output

set compile_cmd [list xvlog -work work -i $rtl_dir]
foreach source [glob [file join $rtl_dir *.v]] { lappend compile_cmd $source }
foreach bench {tb_game_timer tb_oled_status_text tb_top_story44_integration} {
    lappend compile_cmd [file join $tb_dir ${bench}.v]
}
if {[catch {exec {*}$compile_cmd 2>@1} output]} {
    puts $output
    error "xvlog compilation failed"
}
puts $output

foreach {bench snapshot marker} {
    tb_game_timer game_timer_snapshot "PASS: game_timer"
    tb_oled_status_text oled_status_snapshot "PASS: OLED status formatter"
    tb_top_story44_integration top_story44_snapshot "PASS: Story 4.4 top status"
} {
    if {[catch {exec xelab -debug typical -L unisims_ver -top $bench -snapshot $snapshot 2>@1} output]} {
        puts $output
        error "elaboration failed for $bench"
    }
    puts $output
    if {[catch {exec xsim $snapshot -runall 2>@1} output]} {
        puts $output
        error "simulation failed for $bench"
    }
    puts $output
    if {[string first "FAIL" $output] >= 0 || [string first $marker $output] < 0} {
        error "$bench did not pass"
    }
}

puts "PASS: focused Story 4.4 timer, formatting, and OLED integration benches"
