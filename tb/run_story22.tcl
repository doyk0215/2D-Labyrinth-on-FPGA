# Run the Story 2.2 angle-accumulator and sine/cosine benches with Vivado.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set rtl_dir [file join $repo_root rtl]
set run_dir [file join $::env(TEMP) story22_vivado_run]
file mkdir $run_dir
cd $run_dir

set sources [list \
    [file join $rtl_dir sincos_rom.v] \
    [file join $rtl_dir angle_accumulator.v] \
    [file join $repo_root tb tb_sincos_rom.v] \
    [file join $repo_root tb tb_angle_accumulator.v]]
set compile_cmd [list xvlog -work work -i $rtl_dir]
foreach source $sources { lappend compile_cmd $source }

puts "Compiling Story 2.2 sources..."
if {[catch {exec {*}$compile_cmd 2>@1} output]} {
    puts $output
    error "xvlog compilation failed"
}
puts $output

foreach {top snapshot marker} {
    tb_angle_accumulator angle_accumulator_snapshot "PASS: angle_accumulator"
    tb_sincos_rom sincos_snapshot "PASS: sincos_rom matches the model"
} {
    puts "Elaborating $top..."
    if {[catch {exec xelab -debug typical -top $top -snapshot $snapshot 2>@1} output]} {
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

puts "PASS Story 2.2 regression"
