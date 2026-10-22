# Artefact manifest

Generated 2026-10-22 13:54 UTC on the machine that ran the flow.
Sizes let anyone reproducing the run diff their output against ours.

| bytes | file |
|---:|---|
| 1628 | `flow/3_src/cts_cp8d.tcl` |
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
| 418 | `flow/config.json` |
| 64 | `flow/pin_order.cfg` |
| 177807 | `results/cts/alu8_plcts.def` |
| 24648 | `results/floorplan/alu8.def` |
| 145711 | `results/floorplan/alu8_pdn.def` |
| 151801 | `results/placement/alu8_pl.def` |
| 319149 | `results/routing/alu8_rt.def` |
| 46062 | `results/routing/alu8_rt_pwr.v` |
| 18144 | `results/routing/alu8_rt_sim.v` |
| 423 | `results/routing/DRC-RESULT.md` |
| 0 | `results/routing/drc.rpt` |
| 155176 | `results/spef/alu8_rt.spef` |
| 77512 | `results/sta/alu8_rt.sdf` |
| 2188 | `results/sta/timing_report.txt` |
| 9 | `results/sta/tns_report.txt` |
| 9 | `results/sta/wns_report.txt` |
| 20959 | `results/synthesis/alu8_sys.v` |

## Run trees

Added 2026-10-22 14:41 UTC. `runs/` holds the three run directories as produced
by the tool. See `docs/failed-runs.md` for what each one is and why the two
non-completing trees are kept.

| tree | what it is | reached STA? |
|---|---|---|
| `runs/RUN` | the completed run; the files tabled above were lifted from here | yes |
| `runs/RUN_COMPLETE_20261021` | archived snapshot of the same run | yes |
| `runs/RUN.bak` | aborted attempt, 02:15, run-tag collision | no |

`runs/RUN/reports/` and `runs/RUN/logs/` do not appear: they are empty on disk
(raw `run_openroad_script` calls bypass OpenLane's native reporting tree) and
git does not track empty directories.

## Deliberately excluded
- `tmp/` in every run tree — holds `merged.nom.lef`, `merged.min.lef` and
  `merged.max.lef` (484,380 B each) plus `merged.lib` (2,664,059 B),
  `trimmed.lib` (2,664,060 B), `cts.lib` (2,685,635 B), `cts-fastest.lib`
  (2,676,577 B) and `cts-slowest.lib` (2,669,913 B), all copied out of the PDK.
  Roughly 14.5 MB of PDK data per tree.
- `runs/RUN/results/routing.bak/` — byte-identical duplicate of `results/routing/`.
- `3_src/run_sta.tcl.bak` — superseded scratch copy.
- `*.odb` — OpenDB binaries, tool-version-locked and regenerable.
- **All PDK files** (`*.lib`, `*.lef`, tech/DRC/LVS decks, cell GDS). The SCL
  CP8D PDK is not redistributed here; obtain it from SCL Mohali / eChipHub.
