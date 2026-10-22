# Reproducibility — the flow is deterministic

Until 2026-10-22 this flow had been executed **once**, stage by stage, by hand.
It has now been put into a single driver script, [`flow/run_all.tcl`](../flow/run_all.tcl),
and re-run end to end. The artefacts came back **byte-identical**.

## Measurement

| artefact | re-run | original run | match |
|---|---:|---:|:--:|
| `results/placement/alu8_pl.def` | 151,801 | 151,801 | ✅ |
| `results/cts/alu8_plcts.def` | 177,807 | 177,807 | ✅ |
| `results/routing/alu8_rt.def` | 319,149 | 319,149 | ✅ |
| `results/routing/alu8_rt_sim.v` | 18,144 | 18,144 | ✅ |
| `results/routing/alu8_rt_pwr.v` | 46,062 | 46,062 | ✅ |
| `results/routing/drc.rpt` | 0 | 0 | ✅ |

Driver output, verbatim:

```
  OK    151801  .../results/placement/alu8_pl.def
  OK    177807  .../results/cts/alu8_plcts.def
  OK    319149  .../results/routing/alu8_rt.def
  OK     18144  .../results/routing/alu8_rt_sim.v
  OK     46062  .../results/routing/alu8_rt_pwr.v
=== FLOW DONE ===
drc.rpt size (0 == router DRC clean):
  0
```

Post-run checks, both reproduced exactly:

- **Timing** — setup **+88.39 MET** (11.61 ns arrival vs 100.00 required) and
  hold **+0.78 MET** (0.78 vs 0.00). Both corners clean.
- **Fillers** — `grep -c FILLER alu8_rt.def` → **356**, unchanged. This check is
  load-bearing: CP8D ships no tap cell, so fillers carry well and substrate
  continuity. A silent no-op in `fill_cp8d.tcl` would flood signoff DRC.

## Why this matters

Byte-identical reproducibility is what separates a one-off from an engineering
flow. Every number previously reported here is now *reproducible on demand*,
not merely *observed once*.

## The corollary — and it is not comfortable

Placement is deterministic, so the violating cell abutments are identical every
time. **A plain re-run cannot change the DRC result.** Closing the three boron
violations in [`signoff.md`](signoff.md) requires changing an **input** — the
obvious candidate being `PL_TARGET_DENSITY`, since the die sits at only ~33 %
occupancy and has room to spread.

Re-running as-is and hoping for a different answer is not an option the tool
leaves open.

## The guard that makes unattended running safe

`run_all.tcl` carries a `must` proc that asserts each stage produced a
non-empty artefact, and raises a Tcl error otherwise.

This is not theoretical. A dead routing invocation once left a **0-byte**
`alu8_rt.def` on disk; `rcx_cp8d.tcl` then consumed it and aborted with
`DEFPARS-6002 Incomplete def file ... at line 1, on token <unprintable>`, which
was initially misread as a bug in the rcx script itself. The real fault was two
stages upstream. See [`failed-runs.md`](failed-runs.md).

The lesson is not "check less to go faster" — it is **"automate the check"**.
One `must` call per stage costs nothing and converts a silent corruption into a
loud, immediate stop.

`drc.rpt` is deliberately printed rather than asserted: for that one file
**0 bytes means pass**, so a non-empty assertion would be exactly backwards.
