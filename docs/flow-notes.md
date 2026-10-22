# Running a purely combinational design through the SCL CP8D flow

Notes gathered while putting this ALU through OpenLane on SCL's 0.8 µm CP8D PDK.
The SCL reference flow (`project_scl_cp8d`) was built around **cnt8**, a *clocked*
8-bit counter. A combinational design breaks it in three specific places.

---

## 1. There is no clock port

In `config.json`:

```json
"CLOCK_PORT": "",
"CLOCK_NET": "",
"RUN_CTS": false
```

Keep `CLOCK_PERIOD` — it still defines the STA window.

`3_src/run_sta.tcl` ships with:

```tcl
create_clock -name CLK -period $::env(CLOCK_PERIOD) [get_ports clk]
```

which **errors** when no `clk` port exists. Replace it with a virtual clock and zero
I/O delays:

```tcl
create_clock -name vclk -period $::env(CLOCK_PERIOD)
set_input_delay  0.0 -clock vclk [all_inputs]
set_output_delay 0.0 -clock vclk [all_outputs]
```

OpenSTA then reports the **pure input-to-output combinational delay** against the
window. Start at the reference flow's 100 ns placeholder, read the real path delay,
tighten on a second pass if you want a meaningful slack number.

### `CLOCK_PERIOD` does not reach synthesis

Worth knowing before anyone re-runs the whole flow hoping for timing-driven synthesis:
`abc -liberty` is called with **no `-D` and no SDC**, so ABC maps for **area**. The
value only feeds `run_sta.tcl`'s `create_clock`. If you want different timing numbers,
**re-run `run_sta.tcl` alone** — a full re-run buys nothing.

This also explains why Yosys picks gate chains over the `ADR100` full-adder cell: an
area-mode decision, not a library quirk.

---

## 2. 🔴 The filler trap

`routing_cp8d.tcl` carries an SCL comment saying a combinational design may read the
**placement** DEF and skip `cts_cp8d.tcl` entirely. **Following that advice as written
loses every filler cell.**

- `placement_cp8d.tcl` ends at `detailed_placement` + `check_placement` and writes
  `${DESIGN}_pl.def` / `${DESIGN}_plcts.odb`. **It has no `filler_placement`.**
- `cts_cp8d.tcl` is the **only** script that calls `filler_placement`, and it does so
  *after* its clock-tree work — which is unreachable without a clock.

No fillers ⇒ broken nwell and implant continuity ⇒ DRC failures at signoff.

**On this process the stakes are higher than usual:** CP8D ships **no tap cell**, so
the fillers are what carry well/substrate contact continuity across a row. See the tap
cell note in the main README.

### The fix: a CTS-less `3_src/fill_cp8d.tcl`

Keep the filler step and write to the **same `results/cts/` paths**, so
`routing_cp8d.tcl` needs no edit at all:

```tcl
read_liberty <pdk>/cp8d_core_typ.lib
read_lef     <pdk>/tech_cp8d.lef
read_lef     <pdk>/core_cp8d.lef
read_lef     <pdk>/pads_cp8d.lef
read_lef     <pdk>/corner_cp8d.lef
read_db      "$::env(DESIGN_DIR)/runs/RUN/results/placement/${DESIGN_NAME}_plcts.odb"

set_cmd_units -time ns -capacitance pF -resistance kOhm -voltage V -current mA

detailed_placement
set ::env(FP_FILL_CELL) "FILLER1 FILLER2 FILLER3 FILLER4 FILLER5 FILLER6"
filler_placement -prefix FILLER \
    [list "FILLER1" "FILLER2" "FILLER3" "FILLER4" "FILLER5" "FILLER6"]

write_db  "$::env(DESIGN_DIR)/runs/RUN/results/cts/${DESIGN_NAME}_plcts.odb"
write_def "$::env(DESIGN_DIR)/runs/RUN/results/cts/${DESIGN_NAME}_plcts.def"
```

Run it **in place of** `cts_cp8d.tcl`. The filler list is widest-first, which is what
filler insertion wants (`FILLER1` is 124.8 µm wide down to `FILLER6` at 3.9 µm).

Result on this design: **566 components = 210 logic + 356 FILLER**.

---

## 3. Power planning — two metal layers changes the rules

`pdn_cp8d.tcl` as shipped places **metal1 followpins** at 7 µm per row plus a
metal1/metal2 ring, and **every `add_pdn_stripe -layer metal2` line is commented out**.
No vertical straps cross the core. Power enters at the ring and runs inward along each
row rail, fed from both ends, so the worst case is mid-row.

**🔴 Do not uncomment the metal2 stripes.** CP8D has **only two metal layers**, and
`routing_cp8d.tcl` pins signals to exactly those:

```tcl
set_routing_layers -signal metal1-metal2 -clock metal1-metal2
```

Vertical metal2 power straps would consume the only vertical signal routing resource.
In a 6–10 metal process you strap on upper layers and never think about it; at two
metals, power and signal compete for the same tracks. **This tradeoff is one of the
more instructive things about working on a mature node.**

There is also a max-metal-width rule (25 µm on both metal1 and metal2) that the DRC
deck does **not** implement — so an over-wide strap passes DRC and is still
non-compliant.

### A free upgrade nobody has taken

The script already calls `set_pdnsim_net_voltage -net VDD -voltage 5.0` (and GROUND at
0.0) and then **never runs the analyser**. Adding this after `pdngen` produces a real
IR-drop number:

```tcl
catch { analyze_power_grid -net VDD    -outfile .../reports/floorplan/ir_vdd.rpt }
catch { analyze_power_grid -net GROUND -outfile .../reports/floorplan/ir_gnd.rpt }
```

Wrap in `catch` — it may fail for want of switching activity, and that failure is
itself informative.

---

## 4. Practical traps

- **`run_openroad_script` takes a path argument** and prints nothing on success. Check
  `runs/RUN/results/` — and check **sizes**, not just existence. A 0-byte artefact once
  sent this project chasing a nonexistent bug in the extraction script; the real cause
  was a dead routing invocation.
- **STA writes to `results/sta/`, not `reports/`.** `runs/RUN/reports/` and `logs/` stay
  empty forever when you drive the flow with raw `run_openroad_script` calls, because
  that bypasses OpenLane's native report tree. Empty there is not failure.
- **The routed DEF is `alu8_rt.def`**, not `alu8_route.def`. Routing emits three files:
  `_rt.def` (layout), `_rt_pwr.v` (netlist **with** VDD/GROUND, for LVS) and
  `_rt_sim.v` (**without** supply pins, for gate-level simulation).
- **`run_sta.tcl` is DEF-less**, so `estimate_parasitics` cannot work inside it. A
  sibling script that does `read_def` is required, using `-placement` rather than
  `-global_routing`.
- **`sclenv` is a launcher, not sourceable** — it ends in `exec bash --rcfile`, so
  `$PDK_ROOT` expands to `//` in a shell you were already in. Run `sclenv` first, or use
  absolute paths. It also refuses to load if `$CADENCE_ROOT` and `$DDIROOT` are set, as
  a `PDK_ROOT` collision guard.
- **Do not "fix" `PLACE_SITE_HEIGHT 32.35` to 25.35.** Both numbers describe the same
  cell: 25.35 is the LEF `SIZE` / abutment box, 32.35 is the full drawn metal1 extent,
  because the supply rails overhang 3.5 µm top and bottom. Changing it risks shorting
  VDD to GROUND.

---

## Order of work

Get a clean baseline run **first** (0-byte `drc.rpt`), then add instrumentation such as
`analyze_power_grid` and re-run from PDN. Never change two things before one run works.
