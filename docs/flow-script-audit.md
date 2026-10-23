# Flow script audit — what the `3_src` scripts actually do

Read 2026-10-23 from `snapshots/2026-10-22_2127_chip-4mm/3_src/`, which is the
design tree exactly as it stood for the 4 mm chip run. Everything below is quoted
from the committed files. Nothing here is inferred from run outputs.

This audit exists because two separate "the config said X but X never happened"
defects had already been found by accident (`-tag`, `FP_PIN_ORDER_CFG`). Reading the
scripts end to end turned up two more of the same class, and explained a number that
had been sitting unexplained in the records since 21 October.

---

## 1. `GPL_CELL_PADDING` and `DPL_CELL_PADDING` are never applied

`placement_cp8d.tcl`, the entire active body:

```tcl
read_def ".../runs/RUN/results/floorplan/${DESIGN_NAME}_pdn.def"
catch {gui::clear_highlights}
set_thread_count 2
global_placement -density $::env(PL_TARGET_DENSITY)
detailed_placement
check_placement -verbose
write_def ".../runs/RUN/results/placement/${DESIGN_NAME}_pl.def"
write_db  ".../runs/RUN/results/placement/${DESIGN_NAME}_plcts.odb"
```

`set_placement_padding` does not appear. OpenROAD applies padding only through

```tcl
set_placement_padding -global -left N -right N
```

issued before placement, where `N` is counted in **site widths**, not microns.
OpenLane's own placement step builds that call from `GPL_CELL_PADDING` /
`DPL_CELL_PADDING`; `run_openroad_script` bypasses the native step, so both
variables are read into the environment and then ignored.

The as-run `runs/CHIP/config.tcl` carries `GPL_CELL_PADDING "40"` and
`DPL_CELL_PADDING "20"`. Neither reached the placer.

**Why it matters.** The three (later two) boron-width violations are an abutment
artefact — proven by running DRC on a standalone `INVR00`, which is clean across all
71 rule categories (`docs/invr00-standalone-drc.md`). Padding attacks abutment
directly: at a 3.9 µm site width, `-left 1 -right 1` enforces a 3.9 µm gap, against a
violation that is 50 nm short of its 3.4 µm minimum. And unlike lowering density, it
does not scatter cells across the die, which is what created the six via-over-poly
violations at `PL_TARGET_DENSITY 0.05`.

Density was never the only knob. It was the only *connected* one.

---

## 2. The floorplan destroys every odd row — and that is where 50.7 µm comes from

`floorplan_cp8d.tcl`, after `initialize_floorplan`:

```tcl
set block [[ord::get_db_block] getRows]
set count 0
foreach row $block {
    if { [expr $count % 2] != 0 } {
        odb::dbRow_destroy $row
    }
    incr count
}
puts "Custom Row Modification: Removed alternating rows to prevent overlaps."
```

`initialize_floorplan -site CORE` lays rows out on the **SITE height declared in the
tech LEF**, which for CP8D is **25.35 µm**. The standard cells are **32.35 µm** tall.
Rows therefore overlap by 7 µm, and the script deletes every second one to recover a
legal placement surface.

The arithmetic closes a loose end:

```
25.35 × 2 = 50.70 µm
```

which is exactly the "16 rows, 50.7 µm pitch" recorded for the 1 mm run. That pitch
had been logged as an observation with no explanation attached. It is a direct
consequence of this loop.

**Consequences.**

- **18.35 µm of every 50.70 µm row is dead space — 36 % of the core is unusable.**
  Irrelevant at 1.2 % utilisation; fatal to any utilisation figure quoted for a
  denser design.
- `PLACE_SITE_HEIGHT 32.35` in `config.json` is a **workaround for the LEF**, not a
  description of it. The two numbers disagree by design.
- A flow that deletes half its rows to compensate for a library/tech mismatch is not
  tapeout-clean. The honest fix is a corrected SITE definition; the row-destroy loop
  is a workaround that happens to work at very low utilisation.

---

## 3. `place_pins` lives in routing, with no constraints

`routing_cp8d.tcl`:

```tcl
make_tracks metal1 -x_offset 0    -x_pitch 3.7 -y_offset 0 -y_pitch 3.7
make_tracks metal2 -x_offset 1.95 -x_pitch 3.9 -y_offset 0 -y_pitch 3.9

place_pins -hor_layers {metal1} -ver_layers {metal2}
```

There is no `-group_pins`, no `set_io_pin_constraint`, and no reference to any pin
order file. There is no `place_pins` call anywhere in `floorplan_cp8d.tcl`.

So the sequence is: floorplan → **placement with no pin locations at all** →
CTS-substitute fill → routing, where the router finally assigns pins by its own
heuristic.

For a pad-limited die this is backwards. The entire reason `CORE_AREA` was set to the
measured frame opening `304.90 304.90 3695.10 3695.10` was so that pins would land
where the pads are. Placement never saw those positions, so any alignment in the
current result is accidental.

This is the exact line behind the already-recorded finding that
`pin_order_chip.cfg` was never applied. `FP_PIN_ORDER_CFG` is consumed by OpenLane's
native floorplan step, which this flow does not run.

**Fix direction** (not yet scripted, and the option spelling must be confirmed
against `help set_io_pin_constraint` in this OpenROAD build first): constrain each
bus to its edge, and move the call into floorplan so placement is pin-aware.

---

## 4. The floorplan SDC guard can never fire

`floorplan_cp8d.tcl`:

```tcl
if { [file exists $::env(DESIGN_DIR)/check_stdcells/4A_synthesis_netlist/$::env(DESIGN_NAME).sdc] } {
    read_sdc ...
}
```

There is no `check_stdcells/` directory in the design tree — see
`snapshots/2026-10-22_2127_chip-4mm/`. The guard is always false and the floorplan is
timing-blind.

Harmless for a combinational design with a virtual clock, but it reads as a
safeguard while providing none. Worth deleting or repointing rather than leaving in
place.

---

## Smaller notes from the same read

- `global_route -allow_congestion` suppresses congestion failure. At 1.2 %
  utilisation nothing is congested, so this currently hides nothing — but it would
  also hide a genuine problem in a denser design.
- `fill_cp8d.tcl` is what writes `results/cts/alu8_plcts.def`. That is why
  `routing_cp8d.tcl`'s `read_def .../results/cts/...` succeeds even though
  `RUN_CTS` is false and `cts_cp8d.tcl` never runs.
- `routing_cp8d.tcl` carries a commented block documenting exactly how to skip CTS
  for a combinational design. The flow takes a different route to the same place:
  the fill script writes into the CTS path instead.
- `detailed_placement` is called bare; the `-max_displacement {50 50}` variant is
  commented out.

---

## The experiment these findings point to

One run, two knobs, against the two already-measured configurations:

| configuration | boron 6.1.1/6.1.2 | via-to-poly 9.4.1 |
|---|---|---|
| 1 mm die, density 0.45, no padding | 3 | 0 |
| 4 mm die, density 0.05, no padding | 2 | 6 |
| **4 mm die, density 0.20, padding 1 site** | **predicted 0** | **predicted < 6** |

Edit to `placement_cp8d.tcl`, immediately before `global_placement`:

```tcl
set_placement_padding -global -left 1 -right 1
```

Rationale: padding makes hard abutment geometrically impossible, so the boron
violations should go to zero independently of density; density 0.20 sits between the
two measured points and should keep nets short enough to reduce via-over-poly from
the 0.05 result.

Run procedure is the established one — every `3_src` script hardcodes `runs/RUN`, so
`-tag` does nothing: move `runs/RUN` aside first, run as `-tag RUN`, then rename the
result.

⚠️ Editing `placement_cp8d.tcl` breaks the "8 of 10 scripts byte-identical to stock"
provenance claim recorded in `04-projects-work/alu8-3src-hash-verification.md`. That
is a deliberate trade, and the modified file must be noted as a ninth input-side edit.
