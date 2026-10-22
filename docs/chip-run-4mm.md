# The 4 mm chip run — results

**Run 2026-10-23 02:57 IST on W0.** `runs/CHIP/`, config `tapeout/config_chip.json`
(4 mm die, measured core opening, `PL_TARGET_DENSITY 0.05`).

**LVS: netlists match. Router DRC: clean. Signoff DRC: 8 violations — a different
mix from the 1 mm run.**

---

## 1. Stage results

| artefact | 1 mm run | **4 mm run** |
|---|---:|---:|
| `synthesis/alu8_sys.v` | 20,959 | **20,959** — identical |
| `floorplan/alu8.def` | 24,648 | **27,616** |
| `floorplan/alu8_pdn.def` | 145,711 | **397,893** |
| `placement/alu8_pl.def` | 151,801 | **404,259** |
| `cts/alu8_plcts.def` | 177,807 | **571,381** |
| `routing/alu8_rt.def` | 319,149 | **727,713** |
| `routing/alu8_rt_pwr.v` | 46,062 | **154,052** |
| `routing/alu8_rt_sim.v` | 18,144 | **18,144** — identical |
| `routing/drc.rpt` | 0 | **0** — router DRC clean |
| `sta/timing_report.txt` | 2,188 | **2,188** |

Two identities are the consistency check that matters:

- **`alu8_sys.v` byte-identical.** Synthesis never sees the die: `DIE_AREA`,
  `CORE_AREA` and `PL_TARGET_DENSITY` do not reach Yosys, and `CLOCK_PERIOD` does
  not reach ABC. Same 210 cells.
- **`alu8_rt_sim.v` byte-identical.** This netlist is written with
  `-remove_cells {FILLER1..6 CORNER}`, so it is the logic only. Identical means
  the same 210-cell design was routed in both; everything that grew is fillers
  and wiring.

The ~2.3× growth elsewhere is fillers tiling a 3390.2 µm square plus much longer
routes. **Routing did not fail** on two metal layers across that span, which was
the main risk going in.

---

## 2. Signoff DRC — 8 items, and the mix changed

```
2  6.1.1 and 6.1.2 : Minimum Boron width violations =  3.4um
6  9.4.1 : Minimum via to Poly spacing violations = 1.0um
```

Report header verified: `<original-file>` = `5_klayout/lvs_drc/alu8.gds`,
`<top-cell>` = `alu8`.

### 2.1 Boron: 3 → 2 — density helped, and 2 is a threshold

```
edge-pair: (2289.3,549.7;2288.719,549.7)|(2289.3,553.05;2289.881,553.05)
edge-pair: (819,904.6;818.419,904.6)|(819,907.95;819.581,907.95)
```

Identical signature to the 1 mm run: each edge is **0.581 µm** long and the pair
separation is **553.05 − 549.7 = 3.35 µm**, against the 3.4 µm minimum — **50 nm
short**, exactly as before. Same defect, fewer sites.

Combined with the standalone-cell result (`docs/invr00-standalone-drc.md`:
`INVR00` alone is **0 items** across 71 categories), the abutment explanation
holds: dropping utilisation from ~33 % to ~1.2 % removed one of the three sites.

🔴 **Practical consequence: 2 is the `999:0` waiver-layer cap.** At 3 items the
waiver route was unavailable in principle. At 2 it is available. That does not
make it *right* — a waiver should be justified, not used to hit a number — but the
hard blocker is now a soft one.

### 2.2 Via-to-poly: 0 → 6 — caused by the density drop

Measured gaps, from the edge pairs:

| violation | gap (µm) | required |
|---|---:|---:|
| (1990.2 … / 1990.15 …) | **0.05** | 1.0 |
| (985.5 … / 985.65 …) | **0.15** | 1.0 |
| (1753.8 … / 1753.95 …) | **0.15** | 1.0 |
| (1129.8 … / 1129.95 …) | **0.15** | 1.0 |
| (1991.7 … / 1991.95 …) | **0.25** | 1.0 |
| (876.3 … / 876.8 …) | **0.5** | 1.0 |

Not marginal — the worst is 20× under.

**Why the router did not catch them.** `detailed_route` checks what it draws
against the **LEF abstract view**, which models pins and blockages but **not
poly**. Poly exists only in the cell GDS, which signoff flattens and the router
never reads. So `drc.rpt` = 0 and six real violations are both true statements
about different views of the same layout.

**Why spreading the cells created them.** At 1.2 % utilisation the 210 cells sit
far apart, so nets must run long distances **across** standard cells instead of
between neighbours. Every via dropped on such a crossing lands over a cell — and
over poly the router cannot see. The 1 mm run, at 33 %, had short local routes
and never did this.

### 2.3 🔴 The tradeoff this exposes

> **High density → boron violations at cell abutments.
> Low density → via-over-poly violations from long cross-cell routes.**

Neither extreme is clean, so the fix is not a single knob. Candidates, cheapest
first:

1. **Intermediate density.** Sweep `PL_TARGET_DENSITY` between 0.05 and 0.45.
   There may be a window with few enough abutments and short enough routes.
   Cheap: one flow run per point, fully scripted.
2. **Keep density low, stop vias landing on cells.** The honest fix for 9.4.1.
   Needs a routing-side constraint, which on this flow means either a via
   keepout over cell areas or accepting more jogs.
3. **Place the logic compactly inside a large die.** The cells do not have to
   spread to fill 3390 µm. A dense cluster in a corner of the chip core would
   keep routes short — but reintroduces abutment, so it only works combined
   with (1).

**What is now ruled out:** `INVR00` being defective (measured clean standalone),
and tap cells (CP8D ships none; fillers are the tap strategy).

---

## 3. 🔴 `pin_order_chip.cfg` was never applied

The 8 / 8 / 8 / 5 N/S/E/W split exists on paper only.

**`floorplan_cp8d.tcl` contains no `place_pins` call.** The only pin placement in
the whole flow is in `routing_cp8d.tcl`:

```tcl
place_pins -hor_layers {metal1} -ver_layers {metal2}
```

with no `-group` and no reference to the config. `FP_PIN_ORDER_CFG` is consumed
by OpenLane's **native** floorplan step, and this flow bypasses that entirely by
calling `run_openroad_script` on the SCL scripts. So the setting is read into the
environment and never used.

**Why this matters for the tapeout:** the entire reason `CORE_AREA` was set to
the frame's measured core opening was so core pins land where pads are. With pins
auto-placed, that alignment is accidental. Pin position must be controlled before
any pad-ring merge, because bonding is fixed one-to-one with the pin-out.

This does **not** invalidate the run — routing, LVS and timing are all unaffected
by *which* edge a pin sits on. It invalidates only the claim that the floorplan is
pad-frame-ready.

**Fix options:** add `place_pins` with `-group` arguments to `floorplan_cp8d.tcl`
(breaks the byte-identical provenance of that script), or add a pin-constraint
step before routing. Either way it must be done before the frame merge.

---

## 4. Status after this run

| | before | after |
|---|---|---|
| chip-sized floorplan | none | **routed at 4 mm** |
| router DRC | clean at 1 mm | **clean at 4 mm** |
| LVS | matched at 1 mm | **matched at 4 mm** |
| boron violations | 3, above the waiver cap | **2, at the cap** |
| via-to-poly | 0 | **6, new** |
| pin placement | assumed from config | **auto — config never applied** |
| `INVR00` as cause | hypothesis | **ruled out** |

Unchanged: gate-level simulation never run; antenna deck, seal ring and
submission form still absent from the PDK and still blocking on SCL.
