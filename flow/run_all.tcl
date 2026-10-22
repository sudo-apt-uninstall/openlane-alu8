# =============================================================================
#  alu8 — full OpenLane flow driver for SCL CP8D (purely combinational)
# =============================================================================
#
#  Usage, from the OpenLane container:
#
#      ./flow.tcl -design project_scl_cp8d/alu8 -tag RUN -interactive -overwrite
#      % source $::env(DESIGN_DIR)/run_all.tcl
#
#  WHY THIS FILE LIVES AT THE DESIGN ROOT AND NOT IN 3_src/
#  --------------------------------------------------------
#  3_src/ is hash-audited at exactly 11 files to prove that 8 of the 10 SCL
#  reference scripts are byte-identical to upstream.  Adding a 12th file there
#  would invalidate that audit.  This driver is ours, so it sits outside.
#
#  WHAT IS DELIBERATELY ABSENT
#  ---------------------------
#  * cts_cp8d.tcl      — calls [get_ports clk]; this design has no clock port.
#                        fill_cp8d.tcl stands in for it and keeps the fillers.
#  * run_sta_wirerc.tcl — the wire-RC experiment; the file no longer exists on
#                        disk and must be rewritten before it can be re-run.
#
# =============================================================================

set D $::env(DESIGN_DIR)
set R $D/runs/RUN/results

# -----------------------------------------------------------------------------
#  must — assert that a stage actually produced something
#
#  The point of a driver script is to stop checking by hand between stages.
#  The answer is NOT to stop checking, it is to automate the check.  A dead
#  stage otherwise emits a missing or zero-byte artefact and the next stage
#  consumes it silently; that exact failure once produced a corrupt DEF, an
#  rcx DEFPARS-6002 abort, and a wrong root-cause theory that took hours to
#  retract.  See docs/failed-runs.md.
# -----------------------------------------------------------------------------
proc must {f} {
    if {![file exists $f]} { error "STAGE FAILED: missing $f" }
    set s [file size $f]
    if {$s == 0}           { error "STAGE FAILED: 0 bytes $f" }
    puts "  OK [format %9d $s]  $f"
}

# --- synthesis ---------------------------------------------------------------
run_yosys_script    $D/3_src/yosys_script.tcl

# --- floorplan + power -------------------------------------------------------
run_openroad_script $D/3_src/floorplan_cp8d.tcl
run_openroad_script $D/3_src/pdn_cp8d.tcl

# --- placement ---------------------------------------------------------------
run_openroad_script $D/3_src/placement_cp8d.tcl
must $R/placement/alu8_pl.def

# --- filler insertion (CTS substitute) ---------------------------------------
#  On CP8D the library ships no tap/welltap cell: well and substrate contacts
#  are drawn inside the standard cells and inside the fillers.  Filler
#  insertion IS the tap strategy, so this stage is load-bearing, not cosmetic.
run_openroad_script $D/3_src/fill_cp8d.tcl
must $R/cts/alu8_plcts.def

# --- routing -----------------------------------------------------------------
run_openroad_script $D/3_src/routing_cp8d.tcl
must $R/routing/alu8_rt.def
must $R/routing/alu8_rt_sim.v
must $R/routing/alu8_rt_pwr.v

# --- parasitic extraction + timing -------------------------------------------
run_openroad_script $D/3_src/rcx_cp8d.tcl
run_openroad_script $D/3_src/run_sta.tcl

# --- summary -----------------------------------------------------------------
#  drc.rpt is printed, never passed to `must`: for THIS file 0 bytes means PASS,
#  so the generic non-empty assertion would be exactly backwards.
puts "=== FLOW DONE ==="
puts "drc.rpt size (0 == router DRC clean):"
puts "  [file size $R/routing/drc.rpt]"
