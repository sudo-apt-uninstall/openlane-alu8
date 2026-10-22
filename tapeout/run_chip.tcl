# alu8 CHIP-SIZED CORE RUN -- CP8D, combinational (no CTS)
#
# Identical stage list to flow/run_all.tcl. The ONLY difference is the config:
# the die is grown to the 4 mm pad frame and CORE_AREA is set to the frame's
# measured core opening, so the routed core GDS lands on the frame coordinates
# with no translation at merge time.
#
# Run from a SEPARATE design directory so the 1 mm run stays intact:
#
#   designs/project_scl_cp8d/alu8_chip/
#       config.json      <- tapeout/config_chip.json
#       pin_order.cfg    <- tapeout/pin_order_chip.cfg
#       1_RTL/alu8.v     <- same file as the 1 mm run (SystemVerilog, .v extension)
#       3_src/*.tcl      <- same 11 scripts, unchanged
#       run_chip.tcl     <- this file
#
#   ./flow.tcl -design project_scl_cp8d/alu8_chip -tag RUN -interactive -overwrite
#   % source $::env(DESIGN_DIR)/run_chip.tcl
#
# DESIGN_NAME stays "alu8" on purpose: yosys_script.tcl hardcodes
# $::env(DESIGN_NAME).v and every 3_src script keys off the same name, so
# reusing it means ZERO script edits between the two runs.
#
# NOT YET EXECUTED. Nothing in this directory is a run record.

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

puts "=== CHIP CORE FLOW DONE ==="
puts "drc.rpt size (0 == router DRC clean):"
puts "  [file size $R/routing/drc.rpt]"

# --- things to read off this run, which the 1 mm run cannot tell us -----------
#
# 1. ROW COUNT. 3390.2 / 32.35 = 104.8 rows before floorplan_cp8d.tcl's
#    alternating-row-deletion loop, so expect ~52 rows against the 1 mm run's 16.
#
# 2. FILLER COUNT. It will be enormous -- the fillers tile every empty site in a
#    3390 um square, and on CP8D filler insertion IS the tap strategy. Check that
#    fill_cp8d.tcl survives the scale before trusting the DEF.
#
# 3. THE FREE DRC EXPERIMENT. Occupancy drops from ~33 % to ~0.4 % (210 cells in
#    11.5 mm2). If the 3 boron-width violations DISAPPEAR here, the NND200->INVR00
#    hard-abutment hypothesis is confirmed and PL_TARGET_DENSITY is the lever. If
#    they persist at the same in-cell offset, it is an INVR00 library defect.
#    This is the cheapest version of that experiment -- it costs one run.
#
# 4. ROUTING RISK. Two metal layers, pins on a 3390 um boundary, logic occupying
#    ~0.45 mm2. Wires get ~40x longer than the 1 mm run. drc.rpt may stop being
#    0 bytes for ordinary congestion reasons. That is a real result, not a bug.
