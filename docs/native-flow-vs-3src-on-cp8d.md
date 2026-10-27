# Which scripts actually run: OpenLane's native flow vs the PDK's `3_src`

Written 2026-10-27 to settle a specific question — *when a CP8D design is running, whose
Tcl is executing?* — and to record what the PDK's own OpenLane config sets, because
several variables are **live on one path and dead on the other**.

---

## 1. The short answer for the parallel `alu` run

**OpenLane's own scripts. The PDK's `3_src` scripts are not involved at all** — the
`project_scl_cp8d` folder was never copied into that OpenLane tree, so `3_src` does not
exist there.

Evidence, all from the run's own command history and logs:

| evidence | reading |
|---|---|
| traceback is `run_placement_step` → `run_placement` → `global_placement_or` → `/openlane/scripts/openroad/gpl.tcl` | `/openlane/scripts/openroad/` is **OpenLane's** directory inside the container. The PDK's would be `$DESIGN_DIR/3_src/placement_cp8d.tcl` |
| `./flow.tcl -design alu -tag runN` — **no `-interactive`** | flow.tcl drives the whole native step sequence itself |
| `run_openroad_script` / `run_yosys_script` never typed, once, in the entire history | those are the *only* way `3_src` scripts ever execute |
| design dir is `designs/alu/` with `src/alu.v` + `config.json` | native layout. The kit's is `designs/project_scl_cp8d/<name>/` with `1_RTL/ 3_src/ 5_klayout/` |
| config keys `VERILOG_FILES`, `FP_SIZING`, `FP_CORE_UTIL`, `DIODE_INSERTION_STRATEGY`, `RUN_CVC`, `FP_PDN_*` | native-only. The kit's `config.json` has **no `VERILOG_FILES` key** — `3_src` finds RTL by `DESIGN_NAME` in `1_RTL/` |
| `grep -rn "FP_PDN" ~/OpenLaneRepo/scripts/openroad/*.tcl` | reading OpenLane's native scripts directly |
| logs at `logs/synthesis/1-synthesis.log`, `reports/floorplan/3-initial_fp_core_area.rpt`, `logs/floorplan/5-pdn.log`, `logs/placement/6-global.log` | the **native numbered-step tree**. On `3_src`, `logs/` and `reports/` stay permanently **empty** |

So the native flow ran: `scripts/openroad/{floorplan,ioplacer,pdn,gpl,dpl,cts,grt,drt,rcx,sta}.tcl`,
orchestrated by `scripts/tcl_commands/*.tcl` — not one line of SCL's physical-design Tcl.

---

## 2. But the PDK is still very much involved

What the native flow consumes from the kit:

```
$PDK_ROOT/scl_cp8d/
├── libs.tech/openlane/
│   ├── config.tcl                      <-- PDK-level variables  (read first)
│   ├── tracks.info
│   └── digital_cp8d/
│       ├── config.tcl                  <-- std-cell-library variables (read second)
│       └── lef/tech_cp8d.lef           <-- TECH_LEF
└── libs.ref/digital_cp8d/{lef,lib,gds} <-- CELL_LEF, CELLS_LEF, LIB_*, GDS_FILES
```

🔴 **This matters more than it first looks: SCL ships a complete, detailed native-flow
configuration.** `libs.tech/openlane/config.tcl` sets PDN geometry, routing layer limits,
placement padding, resizer bypasses, tap-cell switches, IO track pitches and voltages. It
is not a stub.

⇒ **The native flow is an alternative SCL anticipated, not an improvisation.** That said,
only the `3_src` path has ever been taken to a signed-off GDS in this repository, and §4
below is a concrete reason the native path misbehaves out of the box.

---

## 3. Live on one path, dead on the other

`run_openroad_script` executes a `3_src` script *directly*, bypassing OpenLane's native
step wrappers. Any variable consumed only by a wrapper is therefore read into the
environment and never used.

| variable | native flow | `3_src` flow |
|---|---|---|
| `GPL_CELL_PADDING` / `DPL_CELL_PADDING` | **LIVE** | **dead** — `placement_cp8d.tcl` never calls `set_placement_padding` |
| `FP_PIN_ORDER_CFG` | **LIVE** | **dead** — no `place_pins` in `floorplan_cp8d.tcl` |
| `DRC_EXCLUDE_CELL_LIST` / `_OPT` | **LIVE** | dead — belongs to native Magic/KLayout steps |
| `FP_PDN_*` (~25 variables) | **LIVE** | dead — `pdn_cp8d.tcl` hardcodes its own PDN |
| `RUN_CTS` | **LIVE** | advisory — you choose which script to run |
| `PL_TARGET_DENSITY` | LIVE | LIVE (`global_placement -density`) |
| `CLOCK_PERIOD` | LIVE | reaches STA only — `abc` is called with no `-D` |
| alternating-row deletion | **does not happen** | happens in `floorplan_cp8d.tcl` |

---

## 4. 🔴 `GPL_CELL_PADDING 40` — live, enormous, and invisible in the design config

From `libs.tech/openlane/config.tcl`:

```tcl
set ::env(GPL_CELL_PADDING) 40
set ::env(DPL_CELL_PADDING) 20
set ::env(PL_TARGET_DENSITY) 0.2
```

and from `digital_cp8d/config.tcl`:

```tcl
set ::env(PLACE_SITE_WIDTH) 3.9
```

**Padding is counted in placement sites.** 40 sites × 3.9 µm = **156 µm** of padding added
beside every standard cell during global placement, against CP8D cells that are roughly
5–30 µm wide. That inflates each cell's effective footprint by something like **5–20×**.

Consistency check against the failing run's own log: `AveragePlaceInstArea` was
**4,611,525,304** DBU². At `DEF_UNITS_PER_MICRON 1000` that is **4,611.5 µm²** per
instance — which, divided by a 25.35 µm LEF site height, implies an effective cell width
of about **182 µm**. No CP8D standard cell is remotely that wide. **The padding is in the
number.**

Consequences, all consistent with what that run did:

- The placer is solving a problem where the cells occupy far more row length than their
  real area. Raising `DIE_AREA` from 1500 → 1800 and `PL_TARGET_DENSITY` from 0.4 → 0.6
  cannot fix it, because the padding scales with the cell count, not the die.
- `PL_TARGET_DENSITY 0.6` and 40-site padding are **contradictory instructions**: pack
  tightly, and also hold everything 156 µm apart.
- `IdealBinArea = AveragePlaceInstArea / PL_TARGET_DENSITY` holds exactly in that log
  (4,611,525,304 / 0.6 = 7,685,875,506 ≈ the reported 7,685,874,688), so the padded area
  is what the whole bin/density machinery is built on.

**Try `GPL_CELL_PADDING: 0` and `DPL_CELL_PADDING: 0` in the design `config.json` before
touching die area or density again.** It costs one run and is the single highest-value
experiment available on the native path.

⚠️ For context on the other end of the scale: on the `3_src` flow, adding just
`set_placement_padding -global -left 1 -right 1` — **one** site, 3.9 µm — was enough to
eliminate this project's boron-width abutment violations entirely. Forty sites is not a
tuning value.

---

## 5. 🔴 `RUN_CTS 0` in the PDK config — a sequential design gets no clock tree

```tcl
set ::env(RUN_CTS) 0
set ::env(RUN_PRE_CTS_STA) 0
set ::env(RUN_POST_CTS_STA) 0
```

SCL's default is **CTS off**, which suits the combinational and ring-oscillator examples
the kit ships. A **clocked** design inheriting that default gets its clock distributed as
an ordinary unbuffered net: no skew balancing, no insertion-delay control. It will
complete and it will look fine; the clock just isn't engineered.

Also note `CLOCK_PORT "CLK"` (uppercase) and `CLOCK_NET "CLK"` are the PDK defaults — a
design with a lowercase `clk` must override both, or the tool constrains a port that
doesn't exist.

**If your design has flops, set `"RUN_CTS": 1` explicitly in the design config.**

---

## 6. ⚠️ Correction: metal2 power straps are not categorically forbidden

`docs/wsl-openlane-setup.md` §0.5 says that setting `FP_PDN_VERTICAL_LAYER: metal2` puts
power on the only vertical signal layer, and that SCL comment out every
`add_pdn_stripe -layer metal2`. **Both statements are true of `3_src/pdn_cp8d.tcl`.** They
are **not** the whole picture:

```tcl
# libs.tech/openlane/config.tcl
set ::env(FP_PDN_RAIL_LAYER) metal1
set ::env(FP_PDN_VERTICAL_LAYER) metal2
set ::env(FP_PDN_HORIZONTAL_LAYER) metal1
set ::env(FP_PDN_VPITCH) 60
set ::env(FP_PDN_HPITCH) 60
set ::env(FP_PDN_HWIDTH) 20
set ::env(FP_PDN_CORE_RING) 1
set ::env(FP_PDN_CORE_RING_VWIDTH) 7
set ::env(FP_PDN_CORE_RING_HWIDTH) 7
```

**SCL themselves specify metal2 vertical straps for the native flow.** So a design config
setting `FP_PDN_VERTICAL_LAYER: metal2` is not inventing anything — it is restating the
PDK default.

The tension is real but it is SCL's, not the user's: the `3_src` script avoids metal2
straps, the native config mandates them, and both ship in the same kit. On a 2-metal
process with `RT_MIN_LAYER metal1` / `RT_MAX_LAYER metal2`, vertical straps every 60 µm do
consume vertical routing resource — which is presumably why the native config *also*
carries

```tcl
set ::env(GRT_LAYER_ADJUSTMENTS) "0.0,0.5"   # metal1 0% reduction, metal2 50%
set ::env(DRT_OPT_ITERS) 400
```

i.e. it tells the global router that half of metal2 is already gone, and gives the
detailed router 400 iterations to cope.

**Net advice is unchanged — on `3_src` there are no `FP_PDN_*` variables to tune, because
`pdn_cp8d.tcl` does the work — but "SCL forbids metal2 straps" overstates it.**

---

## 7. Other facts worth having from the PDK's native config

- **`FP_IO_VOFFSET` / `FP_IO_HOFFSET` = `304.9`.** That is the same **304.90 µm** we
  measured independently as the 4 mm pad-frame core opening and used for `CORE_AREA`.
  Independent corroboration of that number, from SCL's own file.
- **`FP_TAPS_INSERTION 0` and `RUN_TAP_DECAP_INSERTION 0`** — SCL explicitly disable tap
  insertion, consistent with CP8D shipping no tap/welltap cell. `RUN_FILL_INSERTION 1`
  with `FP_FILL_CELL "FILLER1 … FILLER6"` is how substrate continuity is actually achieved.
- **`SYNTH_STRATEGY "AREA 0"`** — confirms, from the config rather than by inference, that
  synthesis maps for area. This is why an adder becomes a gate carry chain rather than
  `ADR100`.
- **`VDD_PIN_VOLTAGE 5.00`, `GND_PIN_VOLTAGE 0.00`**, nets `VDD` / `GROUND`.
- **`QUIT_ON_LINTER_ERRORS 0`** — already off in the PDK config, so the instantiated-stdcell
  linter warning can never halt a flow. Anyone chasing that warning after a failure is
  chasing nothing.
- **`DRT_ALLOW_OFFGRID_PINS 1`** plus
  `HOOK_POST_DETAILED_ROUTING "detailed_route -allow_offgrid_pins true"`.
- **`PL_RESIZER_*` / `GLB_RESIZER_TIMING_OPTIMIZATIONS` all 0, `DISABLE_RESIZER_TIMING_DRIVEN 1`,
  `RUN_SIMPLE_STA 0`** — the resizer is disabled throughout. Worth knowing before blaming
  it for memory use on a failing placement.
- 🔴 **A copy-paste defect in `digital_cp8d/config.tcl`:**

  ```tcl
  set ::env(NO_SYNTH_CELL_LIST) "inv0d0"
  set ::env(DRC_EXCLUDE_CELL_LIST) "inv0d0"
  set ::env(DRC_EXCLUDE_CELL_LIST_OPT) "INVR01"
  ```

  The comments above the first two say they exclude **`INVR01`**, but the value is
  `inv0d0` — a cell name from a different PDK entirely. CP8D has no such cell, so those
  two lines exclude nothing. Only the third does anything. **Do not read SCL's
  `DRC_EXCLUDE_CELL_LIST` entries as evidence about any CP8D cell's quality.**

---

## 8. What to do with this

If the goal is to reproduce or compare against this repository's results, move to the
`3_src` flow — see `docs/wsl-openlane-setup.md`, which follows the kit's own (A)–(J)
procedure. Only that path has produced a signed-off GDS here.

If the native flow is being kept for now, the three things to change first are:

1. `"GPL_CELL_PADDING": 0, "DPL_CELL_PADDING": 0` — §4.
2. `"RUN_CTS": 1` if the design has flops — §5.
3. Nothing about die area or density until (1) has been tested — the padding dominates.

And one hazard the native path carries regardless: **it does not perform SCL's
alternating-row deletion**, so rows sit at the LEF's 25.35 µm pitch while cells are
32.35 µm tall. Rows overlap by 7 µm, and an un-flipped row's VDD rail (y 17.700–28.850)
crosses the next row's GROUND rail (21.850–32.200). Router DRC will not report it. Check
the floorplan row pitch before trusting any native-flow result on this PDK.

---

*Sources: the run's own `bash_history` and error log; PDK files
`libs.tech/openlane/config.tcl`, `libs.tech/openlane/digital_cp8d/config.tcl`,
`libs.ref/digital_cp8d/project_scl_cp8d/sample_project_files_cp8d/{config.json,3_src/script_openlane.tcl}`,
`Readme_0.8u_digital.txt`. No PDK content is reproduced here beyond variable names and
values needed to explain flow behaviour.*
