# Run the Story 2.1 self-checking testbenches with Vivado's command-line simulator.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set run_dir [file join $::env(TEMP) story21_vivado_run]
file mkdir $run_dir
cd $run_dir

set rtl_ps2 [file join $repo_root rtl ps2_mouse.v]
set rtl_mux [file join $repo_root rtl input_mux.v]
set tb_ps2 [file join $repo_root tb ps2_mouse_tb.v]
set tb_mux [file join $repo_root tb input_mux_tb.v]

puts "Compiling Story 2.1 sources with Vivado xvlog..."
if {[catch {exec xvlog -work work $rtl_ps2 $rtl_mux $tb_ps2 $tb_mux 2>@1} compile_output]} {
    puts $compile_output
    error "xvlog compilation failed"
}
puts $compile_output

foreach {top snapshot marker} {
    input_mux_tb input_mux_snapshot "PASS input_mux_tb"
    ps2_mouse_tb ps2_mouse_snapshot "PASS ps2_mouse_tb"
} {
    puts "Elaborating $top..."
    if {[catch {exec xelab -debug typical -top $top -snapshot $snapshot 2>@1} elaborate_output]} {
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
