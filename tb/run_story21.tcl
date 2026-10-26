# Run the Story 2.1 self-checking testbenches with Vivado's command-line simulator.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set run_dir [file join $::env(TEMP) story21_vivado_run]
file mkdir $run_dir
cd $run_dir

set rtl_dir [file join $repo_root rtl]
set vhdl_sources [list \
    [file join $rtl_dir Ps2Interface.vhd] \
    [file join $rtl_dir Mouse_Control.vhd]]
set sources [list \
    [file join $rtl_dir angle_accumulator.v] \
    [file join $rtl_dir sincos_rom.v] \
    [file join $rtl_dir vga_timing.v] \
    [file join $rtl_dir maze_gen.v] \
    [file join $rtl_dir maze_ram.v] \
    [file join $rtl_dir render.v] \
    [file join $rtl_dir seed_source.v] \
    [file join $rtl_dir ps2_mouse.v] \
    [file join $rtl_dir input_mux.v] \
    [file join $rtl_dir menu_ctrl.v] \
    [file join $rtl_dir oled_clk_div.v] \
    [file join $rtl_dir oled_xy.v] \
    [file join $rtl_dir font_rom.v] \
    [file join $rtl_dir oled_text_pixel.v] \
    [file join $rtl_dir Oled_Display.v] \
    [file join $rtl_dir My_Top_Module.v] \
    [file join $repo_root tb ps2_mouse_tb.v] \
    [file join $repo_root tb input_mux_tb.v] \
    [file join $repo_root tb tb_top_story21_integration.v]]

puts "Compiling Story 2.1 VHDL, RTL, and testbenches with Vivado xvhdl/xvlog..."
set vhdl_compile_cmd [list xvhdl -work work]
foreach source $vhdl_sources { lappend vhdl_compile_cmd $source }
if {[catch {exec {*}$vhdl_compile_cmd 2>@1} vhdl_compile_output]} {
    puts $vhdl_compile_output
    error "xvhdl compilation failed"
}
puts $vhdl_compile_output

set compile_cmd [list xvlog -work work -i $rtl_dir]
foreach source $sources { lappend compile_cmd $source }
if {[catch {exec {*}$compile_cmd 2>@1} compile_output]} {
    puts $compile_output
    error "xvlog compilation failed"
}
puts $compile_output

foreach {top snapshot marker} {
    input_mux_tb input_mux_snapshot "PASS input_mux_tb"
    ps2_mouse_tb ps2_mouse_snapshot "PASS ps2_mouse_tb"
    tb_top_story21_integration top_story21_snapshot "PASS top Story 2.1 integration"
} {
    puts "Elaborating $top..."
    if {[catch {exec xelab -debug typical -L unisims_ver -top $top -snapshot $snapshot 2>@1} elaborate_output]} {
        puts $elaborate_output
        error "xelab failed for $top"
    }
    puts $elaborate_output

    puts "Running $top..."
    if {[catch {exec xsim $snapshot -runall 2>@1} sim_output]} {
        puts $sim_output
        error "xsim failed for $top"
    }
    puts $sim_output
    if {[string first "FAIL" $sim_output] >= 0} {
        error "$top reported a failure"
    }
    if {[string first $marker $sim_output] < 0} {
        error "$top did not print its PASS marker"
    }
}

puts "PASS Story 2.1 Vivado regression"
