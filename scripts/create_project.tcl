# Recreate the Vivado project from the repository sources.
# Usage (from the repository root):  vivado -mode batch -source scripts/create_project.tcl
# Or in the Vivado Tcl console:      cd <repo root>; source scripts/create_project.tcl
# Vivado 2025.2, part XC7A35T-1CPG236C (Basys 3). The generated project goes in vivado/ (git-ignored).

set repo [file normalize [file join [file dirname [info script]] ..]]
create_project -force labyrinth [file join $repo vivado] -part xc7a35tcpg236-1

# Design sources (Verilog/VHDL) and the shared header
set rtl_files [glob -nocomplain [file join $repo rtl *.v]]
if {[llength $rtl_files] > 0} { add_files -norecurse $rtl_files }
set vhdl_files [glob -nocomplain [file join $repo rtl *.vhd]]
if {[llength $vhdl_files] > 0} { add_files -norecurse $vhdl_files }
set hdr [file join $repo rtl labyrinth_pkg.vh]
add_files -norecurse $hdr
set_property file_type {Verilog Header} [get_files $hdr]
set_property include_dirs [list [file join $repo rtl]] [get_filesets sources_1]
set_property target_language Verilog [current_project]
set_property top top [get_filesets sources_1]

# Constraints
add_files -fileset constrs_1 -norecurse [file join $repo constraints basys3.xdc]

# Testbenches (simulation sources)
set tb_files [glob -nocomplain [file join $repo tb *.v]]
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 -norecurse $tb_files
    set_property top tb_rotated_render [get_filesets sim_1]
}
set_property include_dirs [list [file join $repo rtl]] [get_filesets sim_1]

puts "Project created in [file join $repo vivado]"
