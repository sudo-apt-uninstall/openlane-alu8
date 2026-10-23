# =============================================================================
#  alu8 — CHIP-TARGET core hardening run, SCL CP8D, 4 mm frame
# =============================================================================
#
#  🔴 READ THIS FIRST — THE RUN TAG IS A TRAP
#  ------------------------------------------
#  Every script in 3_src HARDCODES the path $DESIGN_DIR/runs/RUN/... It does
#  NOT use the -tag value. Verified on W0 2026-10-22:
#
#      yosys_script.tcl    write_verilog .../runs/RUN/results/synthesis/...
#      floorplan_cp8d.tcl  set output_def ".../runs/RUN/results/floorplan/..."
#      routing_cp8d.tcl    read_def  ".../runs/RUN/results/cts/..."
#                          -output_drc ".../runs/RUN/results/routing/drc.rpt"
#                          write_def/write_verilog .../runs/RUN/results/routing/
#
#  (cdl_gds_script.source hardcodes runs/RUN too, for the same reason.)
#
#  So `-tag CHIP` creates runs/CHIP for OpenLane's own bookkeeping and then
#  EVERY STAGE WRITES INTO runs/RUN ANYWAY — silently overwriting whatever run
#  is sitting there. An earlier attempt with -tag CHIP tripped the first `must`
#  because it was looking in runs/CHIP, which nothing ever writes to.
#
#  Two ways to live with this. Do NOT invent a third.
#
#  (A) RENAME FIRST, RUN AS "RUN" — recommended, no script edits:
#
#        cd /home/eda/OpenLane/designs/project_scl_cp8d/alu8
#        mv runs/RUN runs/RUN_1MM_FINAL              # preserve the 1 mm run
#        cp -r 5_klayout/lvs_drc 5_klayout/lvs_drc_1mm
#        cp config.json config_1mm.json              # if not already done
#        cp config_chip.json config.json
#        sclenv && olmount
#        # container:
#        ./flow.tcl -design project_scl_cp8d/alu8 -tag RUN -interactive -overwrite
#        % source $::env(DESIGN_DIR)/run_chip.tcl
#        # host, after:
#        mv runs/RUN runs/CHIP                       # label it
#        cp config_1mm.json config.json              # restore
#
#      -overwrite is safe here only BECAUSE runs/RUN was moved away first.
#
#  (B) Edit all of 3_src to honour the tag. This works but breaks the
#      hash-provenance argument (8 of 10 scripts are currently byte-identical
#      to SCL's upstream), so it is a deliberate trade, not a tidy-up.
#
#  This file assumes (A): R below points at runs/RUN.
#
#  HOW THE CHIP CONFIG IS SELECTED
#  -------------------------------
#  OpenLane reads `config.json` from the design directory. Naming a file
#  `config_chip.json` does NOT select it — it must be copied over config.json,
#  which is why (A) parks the 1 mm one as config_1mm.json first.
#
#  DESIGN_NAME stays "alu8": yosys_script.tcl hardcodes $::env(DESIGN_NAME).v
#  and every 3_src script keys off the same name, so all 11 scripts are reused
#  byte-identically.
#
#  WHAT THIS SCRIPT DOES
#  ---------------------
#  Hardens alu8 as a CORE for the 4 mm pad frame: RTL -> routed, extracted,
#  timed, with the die and pin placement set so the result drops into the frame.
#
#  WHAT IT DOES NOT DO, AND WHY
#  ----------------------------
#  No pad ring, no seal ring. Not omissions of convenience:
#
#    * The pad frame ships as a separate database (frame4mmx4mm.cdl + GDS).
#      SCL's pad-frame guide describes editing that database, so chip assembly
#      happens in the frame, not in OpenLane. The flow ships no pad-placement
#      script of any kind.
#
#    * The SEAL RING IS NOT IN THE PDK. The MPW page says it and its readme
#      "are given in the PDK". A content-level search of the whole CP8D tree —
#      102 directories, 264 files — plus all five SCL PDFs returns ZERO hits for
#      seal, ring, revision or silicon. CORNER.gds and corner_cp8d.lef DO ship
#      and are pad-ring CORNER CELLS, not a seal ring. Do not confuse them.
#      (Measured aside: the 4 mm frame instantiates no corner cells at all —
#      41 instances = 40 pads + OS_SCL_logo$1. Its corners are empty.)
#
#  Writing a speculative pad-ring script here would look finished and be wrong.
#  The rest is staged in tapeout/TAPEOUT-PLAN.md.
#
# =============================================================================

set D $::env(DESIGN_DIR)

# 🔴 NOT runs/CHIP. The 3_src scripts write here and nowhere else.
set R $D/runs/RUN/results

proc must {f} {
    if {![file exists $f]} { error "STAGE FAILED: missing $f" }
    set s [file size $f]
    if {$s == 0}           { error "STAGE FAILED: 0 bytes $f" }
    puts "  OK [format %9d $s]  $f"
}

puts "=== alu8 CHIP run: 4 mm frame, core hardening ==="
puts "    writing into: $R"
puts "    (3_src hardcodes runs/RUN -- see the header of this file)"

# --- synthesis ---------------------------------------------------------------
#  Also writes 4A_synthesis_netlist/alu8_sys.v, which is what floorplan READS.
#  Synthesis output is independent of the die: DIE_AREA, CORE_AREA and
#  PL_TARGET_DENSITY never reach yosys, and CLOCK_PERIOD never reaches abc.
#  So this netlist is byte-identical to the 1 mm run's.
run_yosys_script    $D/3_src/yosys_script.tcl
must $R/synthesis/alu8_sys.v
must $D/4A_synthesis_netlist/alu8_sys.v

# --- floorplan ---------------------------------------------------------------
#  Reads DIE_AREA / CORE_AREA from config.json and places the 29 pins per
#  pin_order_chip.cfg. CORE_AREA 304.90..3695.10 is the MEASURED core opening
#  of frame4mmx4mm.gds, so the routed core lands on the frame's own coordinates
#  and the later merge is an overlay at the origin with no translation step.
#
#  Expect ~52 rows: 3390.2 / 32.35 = 104.8 before the alternating-row-deletion
#  loop halves it. The 1 mm run gave 16.
run_openroad_script $D/3_src/floorplan_cp8d.tcl
must $R/floorplan/alu8.def

# --- power -------------------------------------------------------------------
#  metal1 followpins per row plus the metal1/metal2 ring.
#
#  Do NOT enable the commented-out metal2 stripes in pdn_cp8d.tcl. CP8D has only
#  two metal layers and routing_cp8d.tcl pins signals to exactly those
#  (set_routing_layers -signal metal1-metal2). Vertical metal2 power straps
#  would consume the only vertical signal resource there is.
#
#  Also note the max metal width rule, 25 um on both metals: the DRC deck does
#  NOT implement a max-width check, so a wide strap passes DRC and is still
#  non-compliant. That surfaces at SCL incoming inspection.
run_openroad_script $D/3_src/pdn_cp8d.tcl
must $R/floorplan/alu8_pdn.def

# --- placement ---------------------------------------------------------------
#  PL_TARGET_DENSITY is 0.05 here against 0.45 on the 1 mm run. Cell area is
#  ~0.137 mm2 against an 11.5 mm2 core = ~1.2 % utilisation, so the design is
#  pad-limited; a low target spreads cells toward the pad ring instead of
#  clustering them centrally and routing everything outward.
#
#  🔴 THIS IS ALSO THE DRC FIX ATTEMPT. Standalone INVR00 was measured DRC-CLEAN
#  on 2026-10-22 (0 items, 71 rule categories), so the 3 boron-width violations
#  are an ABUTMENT ARTEFACT, not a library defect -- see docs/invr00-standalone-drc.md.
#  At 1.2 % density the placer has no reason to hard-abut NND200 against INVR00.
#  If signoff on this run returns 0 items, the unwaivable blocker is closed.
run_openroad_script $D/3_src/placement_cp8d.tcl
must $R/placement/alu8_pl.def

# --- filler insertion --------------------------------------------------------
#  CP8D ships NO tap/welltap/subtap cell: 65 LEF macros, 59 Liberty cells, and
#  the six LEF-only ones are exactly FILLER1..FILLER6. Well and substrate
#  contacts are drawn inside the standard cells and inside the fillers, so
#  filler insertion IS the tap strategy on this process. Load-bearing, not
#  cosmetic.
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
#  yields zero capacitance on every net. Any frequency quoted from the STA that
#  follows is CELL DELAY ONLY, typical corner (5 V, 25 C). CP8D ships no
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
puts ""
puts "ON THE HOST, IMMEDIATELY:"
puts "  mv runs/RUN runs/CHIP        ;# label it before anything else writes there"
puts "  cp config_1mm.json config.json"
puts ""
puts "THEN, NOT AUTOMATED HERE:"
puts "  1. Stream out GDS and run KLayout signoff DRC + LVS."
puts "     ../signoff/signoff.sh does this headlessly. NOTE it also hardcodes"
puts "     runs/RUN via cdl_gds_script.source -- pass RUN_TAG to match whatever"
puts "     the directory is called when you run it."
puts "     COUNT THE <item> ELEMENTS. 0 closes the unwaivable DRC blocker."
puts "  2. Gate-level simulation with alu8_rt_sim.v + alu8_rt.sdf."
puts "     Never run; it is the only check that the routed netlist computes."
puts "  3. Chip assembly in the 4 mm frame database: pad ring, then seal ring."
puts "     See tapeout/TAPEOUT-PLAN.md for the blocker list."
