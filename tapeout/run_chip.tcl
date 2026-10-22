# =============================================================================
#  alu8 — CHIP-TARGET core hardening run, SCL CP8D, 4 mm frame
# =============================================================================
#
#  HOW TO SELECT THIS CONFIG  (read this first)
#  --------------------------------------------
#  OpenLane reads `config.json` from the design directory. Naming a file
#  `config_chip.json` does NOT select it. Use a sibling design directory:
#
#      designs/project_scl_cp8d/alu8_chip/
#          config.json    <- copy of tapeout/config_chip.json
#          pin_order_chip.cfg
#          1_RTL/alu8.v   <- same file as the 1 mm run
#          3_src/*.tcl    <- same 11 scripts, unchanged
#          run_chip.tcl   <- this file
#
#      ./flow.tcl -design project_scl_cp8d/alu8_chip -tag CHIP -interactive -overwrite
#      % source $::env(DESIGN_DIR)/run_chip.tcl
#
#  A separate directory AND a separate tag: either alone would protect the
#  1 mm run, both together make it impossible for -overwrite to touch it.
#  (The alternative — same directory, swap config.json, tag CHIP — works too,
#  but leaves the 1 mm config displaced and easy to forget.)
#
#  DESIGN_NAME stays "alu8": yosys_script.tcl hardcodes $::env(DESIGN_NAME).v
#  and every 3_src script keys off the same name, so all 11 scripts are reused
#  byte-identically and the hash-provenance argument still holds.
#
#  WHAT THIS SCRIPT DOES
#  ---------------------
#  It hardens alu8 as a CORE for the 4 mm pad frame: RTL -> routed, extracted,
#  timed, with the die and pin placement set up so the result can be dropped
#  into the frame database.
#
#  WHAT IT DOES NOT DO, AND WHY
#  ----------------------------
#  It does NOT build a pad ring and it does NOT build a seal ring.
#
#  Those are not omissions of convenience. On this PDK:
#
#    * The pad frame ships as a separate database (frame4mmx4mm.cdl plus its
#      GDS). SCL's own pad-frame guide describes editing that database, which
#      means chip assembly happens in the frame, not in OpenLane. The flow
#      ships no pad-placement script of any kind.
#
#    * The SEAL RING IS NOT IN THE PDK. The MPW page states the seal ring and
#      its readme "are given in the PDK". A content-level search of the whole
#      CP8D tree — 102 directories, 264 files — plus all five SCL PDFs returns
#      ZERO hits for seal, ring, revision or silicon.
#      CORNER.gds and corner_cp8d.lef DO ship, and they are pad-ring CORNER
#      CELLS, not a seal ring. Do not mistake one for the other.
#      This must be obtained from SCL before any tapeout submission.
#      (Measured aside: the 4 mm frame instantiates NO corner cells at all —
#      41 instances = 40 pads + OS_SCL_logo$1. Its corners are empty.)
#
#  Writing a speculative pad-ring script here would produce something that
#  looks finished and is wrong. The stages below are the ones that can be run
#  correctly today; the rest is staged in tapeout/TAPEOUT-PLAN.md.
#
# =============================================================================

set D $::env(DESIGN_DIR)
set R $D/runs/CHIP/results

proc must {f} {
    if {![file exists $f]} { error "STAGE FAILED: missing $f" }
    set s [file size $f]
    if {$s == 0}           { error "STAGE FAILED: 0 bytes $f" }
    puts "  OK [format %9d $s]  $f"
}

puts "=== alu8 CHIP run: 4 mm frame, core hardening ==="

# --- synthesis ---------------------------------------------------------------
run_yosys_script    $D/3_src/yosys_script.tcl
must $R/synthesis/alu8_sys.v

# --- floorplan ---------------------------------------------------------------
#  Reads DIE_AREA / CORE_AREA from config.json and places the 29 pins per
#  pin_order_chip.cfg. CORE_AREA 304.90..3695.10 is the MEASURED core opening
#  of frame4mmx4mm.gds, so the routed core lands on the frame's own coordinates
#  and the later merge is an overlay at the origin with no translation step.
#
#  Expect ~52 rows: 3390.2 / 32.35 = 104.8 before floorplan_cp8d.tcl's
#  alternating-row-deletion loop halves it. The 1 mm run gave 16.
run_openroad_script $D/3_src/floorplan_cp8d.tcl
must $R/floorplan/alu8.def

# --- power -------------------------------------------------------------------
#  metal1 followpins per row plus the metal1/metal2 ring.
#
#  Do NOT enable the commented-out metal2 stripes in pdn_cp8d.tcl. CP8D has
#  only two metal layers and routing_cp8d.tcl pins signals to exactly those
#  (set_routing_layers -signal metal1-metal2). Vertical metal2 power straps
#  would consume the only vertical signal resource there is.
#
#  Also note the max metal width rule, 25 um on both metal1 and metal2: the
#  DRC deck does NOT implement a max-width check, so a wide strap passes DRC
#  and is still non-compliant. That surfaces at SCL incoming inspection.
run_openroad_script $D/3_src/pdn_cp8d.tcl
must $R/floorplan/alu8_pdn.def

# --- placement ---------------------------------------------------------------
#  PL_TARGET_DENSITY is 0.05 here against 0.45 on the 1 mm run. Cell area is
#  ~0.137 mm2 against an 11.5 mm2 core = ~1.2 % utilisation, so the design is
#  pad-limited; a low target spreads cells toward the pad ring instead of
#  clustering them centrally and routing everything outward.
#
#  THIS IS ALSO THE FREE DRC EXPERIMENT. The 3 boron-width violations are
#  hypothesised to come from NND200->INVR00 HARD ABUTMENT. At 1.2 % density the
#  placer has no reason to abut anything. If they vanish, the hypothesis is
#  confirmed and density is the lever. If they survive at the same in-cell
#  offset (dx=0.00, dy=+17.35/+20.70), it is an INVR00 library defect.
run_openroad_script $D/3_src/placement_cp8d.tcl
must $R/placement/alu8_pl.def

# --- filler insertion --------------------------------------------------------
#  CP8D ships NO tap/welltap/subtap cell: 65 LEF macros, 59 Liberty cells, and
#  the six LEF-only ones are exactly FILLER1..FILLER6. Well and substrate
#  contacts are drawn inside the standard cells and inside the fillers, so
#  filler insertion IS the tap strategy on this process. This stage is
#  load-bearing, not cosmetic.
#
#  Expect a very large filler count: they tile every empty site in a 3390 um
#  square. Check fill_cp8d.tcl survives the scale before trusting the DEF.
#
#  Never run cts_cp8d.tcl: it calls [get_ports clk] and this design has none.
run_openroad_script $D/3_src/fill_cp8d.tcl
must $R/cts/alu8_plcts.def

# --- routing -----------------------------------------------------------------
#  Risk to expect: two metal layers, pins on a 3390 um boundary, logic in
#  ~0.137 mm2. Wires get far longer than the 1 mm run. drc.rpt may stop being
#  0 bytes for ordinary congestion reasons. That is a real result, not a bug.
run_openroad_script $D/3_src/routing_cp8d.tcl
must $R/routing/alu8_rt.def
must $R/routing/alu8_rt_sim.v
must $R/routing/alu8_rt_pwr.v

# --- extraction and timing ---------------------------------------------------
#  The SPEF carries connectivity only: the OpenRCX rule deck for this process
#  yields zero capacitance on every net. Any frequency quoted from the STA
#  that follows is CELL DELAY ONLY, typical corner (5 V, 25 C). CP8D ships no
#  worst-case library. Never present it as signoff timing.
run_openroad_script $D/3_src/rcx_cp8d.tcl
run_openroad_script $D/3_src/run_sta.tcl
must $R/sta/timing_report.txt

# --- summary -----------------------------------------------------------------
#  drc.rpt is printed, never asserted: for THIS file 0 bytes means PASS, so a
#  non-empty assertion would be exactly backwards.
puts ""
puts "=== CORE HARDENING DONE ==="
puts "router drc.rpt size (0 == clean):  [file size $R/routing/drc.rpt]"
puts "FILLER instances in routed DEF:    (expect a non-zero count)"
puts ""
puts "NEXT, AND NOT AUTOMATED HERE:"
puts "  1. Stream out GDS and run KLayout signoff DRC + LVS."
puts "     ../signoff/signoff.sh does this headlessly once its deck -rd"
puts "     variable names have been confirmed once on this machine."
puts "     The 3 boron-width violations on INVR00 must be resolved first;"
puts "     they are reproducible and cannot be waived (the 999:0 waiver"
puts "     layer is hard-capped at 2 polygons and there are 3)."
puts "  2. Gate-level simulation with alu8_rt_sim.v + alu8_rt.sdf."
puts "     Never run; it is the only check that the routed netlist computes."
puts "  3. Chip assembly in the 4 mm frame database: pad ring, then seal ring."
puts "     See tapeout/TAPEOUT-PLAN.md for the blocker list."
