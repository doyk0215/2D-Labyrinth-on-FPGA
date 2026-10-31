# Compile current RTL and run the supported Story 1.1–4.4 regression plus Story 3.3.
# Run with Vivado Simulator 2025.2.
set script_path [info script]
if {[file pathtype $script_path] ne "absolute"} {
    set script_path [file join [pwd] $script_path]
}
set repo_root [file dirname [file dirname $script_path]]
set run_dir [file join $::env(TEMP) current_stories_vivado_run]
file mkdir $run_dir
cd $run_dir
set rtl_dir [file join $repo_root rtl]
set tb_dir [file join $repo_root tb]

set vhdl_compile_cmd [list xvhdl -work work \
    [file join $rtl_dir Ps2Interface.vhd] \
    [file join $rtl_dir Mouse_Control.vhd]]
puts "Compiling the PS/2 mouse VHDL sources with Vivado xvhdl..."
if {[catch {exec {*}$vhdl_compile_cmd 2>@1} vhdl_output]} {
    puts $vhdl_output
    error "xvhdl compilation failed"
}
puts $vhdl_output

set compile_cmd [list xvlog -work work -i $rtl_dir]
foreach source [glob [file join $rtl_dir *.v]] { lappend compile_cmd $source }
foreach source [glob [file join $tb_dir *.v]] { lappend compile_cmd $source }

puts "Compiling all current RTL and testbenches..."
if {[catch {exec {*}$compile_cmd 2>@1} output]} {
    puts $output
    error "xvlog compilation failed"
}
puts $output

foreach {top snapshot marker} {
    tb_vga_timing vga_timing_snapshot "PASS: 800x525 totals"
    tb_render render_snapshot "PASS: generated maze"
    tb_rotated_render rotated_render_snapshot "PASS: rotated renderer"
    tb_goal_detection goal_detection_snapshot "PASS: goal detection"
    tb_win_render win_render_snapshot "PASS: win render"
    tb_top_win_indication top_win_snapshot "PASS: top win indication"
    tb_top_story33_control top_story33_control_snapshot "PASS: Story 3.3 goal detector"
    tb_top_rotation top_rotation_snapshot "PASS: top rotation command"
    tb_maze_gen maze_gen_snapshot "PASS: maze_gen"
    tb_game_ctrl game_ctrl_snapshot "PASS: game_ctrl"
    tb_menu_ctrl menu_ctrl_snapshot "PASS: menu_ctrl"
    tb_top_story14_integration top_story14_snapshot "PASS: Story 1.4 top"
    tb_top_story42_integration top_story42_snapshot "PASS: Story 4.2 top"
    tb_top_story43_integration top_story43_snapshot "PASS: Story 4.3 top"
    tb_game_timer game_timer_snapshot "PASS: game_timer"
    tb_oled_status_text oled_status_snapshot "PASS: OLED status formatter"
    tb_top_story44_integration top_story44_snapshot "PASS: Story 4.4 top status"
    tb_top_story34_reset top_story34_reset_snapshot "PASS: Story 3.4 reset"
    tb_story34_frame_budget story34_frame_budget_snapshot "PASS: Story 3.4 physics frame budget"
    input_mux_tb input_mux_snapshot "PASS input_mux_tb"
    tb_top_story21_integration top_story21_snapshot "PASS top Story 2.1 integration"
    tb_sincos_rom sincos_snapshot "PASS: sincos_rom matches the model"
    tb_angle_accumulator angle_snapshot "PASS: angle_accumulator"
    tb_snap_rotation snap_rotation_snapshot "PASS: snap rotation"
    tb_ball_physics ball_physics_snapshot "PASS: ball_physics"
    tb_ball_overlay ball_overlay_snapshot "PASS: ball_overlay"
    tb_top_ball top_ball_snapshot "PASS: top ball"
} {
    puts "Elaborating $top..."
    if {[catch {exec xelab -debug typical -L unisims_ver -top $top -snapshot $snapshot 2>@1} output]} {
        puts $output
        error "xelab failed for $top"
    }
    puts $output

    puts "Running $top..."
    if {[catch {exec xsim $snapshot -runall 2>@1} output]} {
        puts $output
        error "xsim failed for $top"
    }
    puts $output
    if {[string first "FAIL" $output] >= 0} {
        error "$top reported a failure"
    }
    if {[string first $marker $output] < 0} {
        error "$top did not print its PASS marker"
    }
}

# The OLED display benches need the Vivado glbl model and a generic per mode,
# so they run from their own script.
source [file join $tb_dir run_oled_display.tcl]

puts "PASS regression for current RTL through Story 4.4, including both OLED display modes"
