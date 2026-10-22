# Artefact manifest

Sizes let anyone reproducing the run diff their output against ours.

## Flow inputs

| bytes | file |
|---:|---|
| 418 | `flow/config.json` |
| 64 | `flow/pin_order.cfg` |
| 926 | `flow/run_all.tcl` — our driver; runs the whole flow from one `source` |
| 1628 | `flow/3_src/cts_cp8d.tcl` — **never executed**, see README |
| 937 | `flow/3_src/fill_cp8d.tcl` |
| 1608 | `flow/3_src/floorplan_cp8d.tcl` |
| 2444 | `flow/3_src/pdn_cp8d.tcl` |
| 2007 | `flow/3_src/pdn_order.tcl` |
| 1294 | `flow/3_src/placement_cp8d.tcl` |
| 897 | `flow/3_src/rcx_cp8d.tcl` |
| 2528 | `flow/3_src/routing_cp8d.tcl` |
| 1511 | `flow/3_src/run_sta.tcl` |
| 481 | `flow/3_src/script_openlane.tcl` |
| 859 | `flow/3_src/yosys_script.tcl` |

## Flow results

Lifted from `runs/RUN/results/`. Byte-identical across both completed run trees.

| bytes | file |
|---:|---|
| 20959 | `results/synthesis/alu8_sys.v` |
| 24648 | `results/floorplan/alu8.def` |
| 145711 | `results/floorplan/alu8_pdn.def` |
| 151801 | `results/placement/alu8_pl.def` |
| 177807 | `results/cts/alu8_plcts.def` |
| 319149 | `results/routing/alu8_rt.def` |
| 46062 | `results/routing/alu8_rt_pwr.v` |
| 18144 | `results/routing/alu8_rt_sim.v` |
| 0 | `results/routing/drc.rpt` — **0 bytes is the result**: router DRC clean |
| 423 | `results/routing/DRC-RESULT.md` |
| 155176 | `results/spef/alu8_rt.spef` |
| 77512 | `results/sta/alu8_rt.sdf` |
| 2188 | `results/sta/timing_report.txt` |
| 9 | `results/sta/tns_report.txt` |
| 9 | `results/sta/wns_report.txt` |

## Signoff

Added 2026-10-22. Produced by `signoff/cdl_gds_script.source` plus KLayout DRC
and LVS run by hand in the GUI. See [`docs/signoff.md`](docs/signoff.md).

| bytes | file | what it is |
|---:|---|---|
| 2755 | `signoff/cdl_gds_script.source` | the signoff driver — **an input**, retargeted from the counter smoke test |
| 2760 | `signoff/cdl_gds_script.source.bak` | the unmodified template it was derived from |
| 5429 | `signoff/signoff.sh` | **headless replacement** for the above: same CDL and GDS steps, then DRC and LVS in batch. **Not yet executed** — the KLayout decks are PDK files and are not in this repo, so the script inspects them and prints the variables they reference rather than guessing the `-rd` names. Git stores it `100644`; `chmod +x` after checkout |
| 7133 | `signoff/script/def2gds.py` | DEF → GDS, SCL-supplied |
| 7291 | `signoff/script/verilog2spice.py` | Verilog → CDL, SCL-supplied |
| 12191 | `signoff/lvs_drc/scl_drc.txt` | **DRC report: 3 boron-width violations** |
| 22347 | `signoff/lvs_drc/alu8.cdl` | source netlist for LVS, from `alu8_rt_pwr.v` |
| 42167 | `signoff/lvs_drc/alu8_extracted.cir` | netlist extracted from the layout |
| 662694 | `signoff/lvs_drc/alu8.lvsdb` | **LVS database: 0 errors.** The verdict exists only here — open it in KLayout's Netlist Browser |
| 435244 | `signoff/lvs_drc/alu8.gds` | streamed-out layout, written by `def2gds.py` |
| 435244 | `signoff/lvs_drc/alu8_klayout.gds` | the GUI's re-save of the same layout. **Not byte-identical** (57 % of bytes differ, cell write order changed) but **geometrically identical** — verified by parsing both: 30 cells, 7,383 elements, 7,639 XY records, matching layer and `SREF` histograms. See `docs/signoff.md` §4.3 |
| 35628 | `signoff/lvs_drc/DRC_ERROR_SCREENSHOT.png` | KLayout zoomed to one of the three boron-width violations, showing the edge-pair markers that bound the 3.35 µm gap. Marker geometry checked against the report by ratio: 5.66:1 measured vs 5.77:1 reported. See `docs/signoff.md` §3 |

**Excluded from `signoff/`:** `core_iolib_cp8d.cdl` (123,613 B) — a PDK-derived
cell netlist, not redistributed here.

## Tapeout inputs

Added 2026-10-22. **None of these have been executed.** They are the chip-level
inputs for a 4 mm pad-framed version, plus the gap register that says why it is
not a tapeout. See [`tapeout/TAPEOUT-PLAN.md`](tapeout/TAPEOUT-PLAN.md).

| bytes | file | what it is |
|---:|---|---|
| 437 | `tapeout/config_chip.json` | 4 mm die; `CORE_AREA 304.90 304.90 3695.10 3695.10` — the frame's **measured** core opening, so the core GDS merges onto the frame with no translation |
| 64 | `tapeout/pin_order_chip.cfg` | 29 pins as **8 / 8 / 8 / 5**. Every frame edge has exactly 8 signal positions, so the 1 mm run's E-edge grouping of 10 does not fit |
| 3122 | `tapeout/run_chip.tcl` | same stage list as `flow/run_all.tcl`, chip config, separate design directory |
| 11576 | `tapeout/TAPEOUT-PLAN.md` | measured frame geometry, pad-conversion arithmetic (**13 minimum, 18 for a bus-aligned floorplan**), the three SCL-side blockers, and the unwaivable DRC item |

## Run trees

`runs/` holds the raw run directories as produced by the tool. See
[`docs/failed-runs.md`](docs/failed-runs.md) for what each one is.

| tree | what it is | reached STA? |
|---|---|---|
| `runs/RUN` | the 2026-10-22 scripted re-run (`run_all.tcl`) | yes |
| `runs/RUN_COMPLETE_20261021` | the original 2026-10-21 run, executed by hand | yes |
| `runs/RUN.bak` | aborted attempt, 02:15, run-tag collision | no |

Top-level files differ between the two completed trees because the entry points
differed; their `results/` are byte-identical, which is the determinism claim in
auditable form:

| file | `RUN` | `RUN_COMPLETE_20261021` |
|---|---:|---:|
| `config.tcl` | 18232 | 83 |
| `cmds.log` | 8011 | 8593 |
| `openlane.log` | 188 | 1661 |
| `errors.log` | absent | 1435 |

`runs/*/reports/` and `runs/*/logs/` do not appear: they are empty on disk (raw
`run_openroad_script` calls bypass OpenLane's native reporting tree) and git does
not track empty directories.

## Deliberately excluded

- `tmp/` in every run tree — holds `merged.nom.lef`, `merged.min.lef` and
  `merged.max.lef` (484,380 B each) plus `merged.lib` (2,664,059 B),
  `trimmed.lib` (2,664,060 B), `cts.lib` (2,685,635 B), `cts-fastest.lib`
  (2,676,577 B) and `cts-slowest.lib` (2,669,913 B), all copied out of the PDK.
  Roughly 14.5 MB of PDK data per tree.
- `results/routing.bak/` — byte-identical duplicate of `results/routing/`.
- `3_src/run_sta.tcl.bak` — superseded scratch copy.
- `*.odb` — OpenDB binaries, tool-version-locked and regenerable.
- **All PDK files** (`*.lib`, `*.lef`, tech/DRC/LVS decks, cell GDS). The SCL
  CP8D PDK is not redistributed here; obtain it from SCL Mohali / eChipHub.
