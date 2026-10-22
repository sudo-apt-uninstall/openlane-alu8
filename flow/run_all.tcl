# alu8 full flow — CP8D, combinational (no CTS)
set D $::env(DESIGN_DIR)
set R $D/runs/RUN/results

proc must {f} {
    if {![file exists $f]} { error "STAGE FAILED: missing $f" }
    set s [file size $f]
    if {$s == 0}           { error "STAGE FAILED: 0 bytes $f" }
    puts "  OK [format %9d $s]  $f"
}

run_yosys_script    $D/3_src/yosys_script.tcl
run_openroad_script $D/3_src/floorplan_cp8d.tcl
run_openroad_script $D/3_src/pdn_cp8d.tcl
run_openroad_script $D/3_src/placement_cp8d.tcl
must $R/placement/alu8_pl.def

run_openroad_script $D/3_src/fill_cp8d.tcl
must $R/cts/alu8_plcts.def

run_openroad_script $D/3_src/routing_cp8d.tcl
must $R/routing/alu8_rt.def
must $R/routing/alu8_rt_sim.v
must $R/routing/alu8_rt_pwr.v

run_openroad_script $D/3_src/rcx_cp8d.tcl
run_openroad_script $D/3_src/run_sta.tcl

puts "=== FLOW DONE ==="
puts "drc.rpt size (0 == router DRC clean):"
puts "  [file size $R/routing/drc.rpt]"

