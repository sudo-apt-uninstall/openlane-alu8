# Padding run — `runs/PAD_D020`

**Date:** 2026-10-23, 19:47–20:07 IST
**Change under test:** `set_placement_padding -global -left 1 -right 1` added to
`3_src/placement_cp8d.tcl`, with `PL_TARGET_DENSITY` 0.05 → **0.20**, 4 mm die.
**Headline: the boron-width violations are gone. The blocker that could not be
waived is closed.**

---

## 1. Why padding was tried

`GPL_CELL_PADDING 40` and `DPL_CELL_PADDING 20` are set in the config and **never
reach the placer** — `placement_cp8d.tcl` calls `global_placement` and
`detailed_placement` but never `set_placement_padding`, and `run_openroad_script`
bypasses the OpenLane step that would have built that call. See
`docs/flow-script-audit.md`.

So the boron-vs-via tradeoff was never a two-sided dilemma. There was a second knob
and it was disconnected. Padding attacks abutment directly: at a 3.9 µm site width,
one site of padding on each side forces a 3.9 µm gap, against a violation that was
50 nm short of its 3.4 µm minimum.

Syntax confirmed in this OpenROAD build before editing anything:

```
set_placement_padding -global|-masters masters|-instances insts
   [-right site_count] [-left site_count] [instances]
```

## 2. Results

| metric | 1 mm, 0.45, no pad | 4 mm, 0.05, no pad | **4 mm, 0.20, pad 1 site** |
|---|---|---|---|
| boron `6.1.1/6.1.2` | 3 | 2 | **0** |
| via-to-poly `9.4.1` | 0 | 6 | **8** |
| LVS | match | match | **match** |
| router `drc.rpt` | 0 B | 0 B | **0 B** |
| `alu8_rt.def` | 319,149 | 727,713 | **721,360** |
| `alu8_rt_pwr.v` | 46,062 | 154,052 | **152,956** |
| `placement/alu8_pl.def` | — | 404,259 | **404,121** |
| `cts/alu8_plcts.def` | — | 571,381 | **569,641** |
| FILLER instances | 356 | 2,214 | **2,197** |
| setup slack | +88.39 MET | +88.39 MET | **+88.39 MET** |
| hold slack | +0.78 MET | +0.78 MET | **+0.78 MET** |

The DRC report lists **one** category only:

```
8 '9.4.1 : Minimum via to Poly spacing violations = 1.0um'
```

`6.1.1 and 6.1.2 : Minimum Boron width` appears in the category list, as it does in
every run, with **no items under it**. Zero violations across all 71 rule categories
except via-to-poly.

That padding actually reached the placer is independently visible: the placement DEF
changed size, 404,259 → 404,121.

## 3. What this settles

**The boron violations were an abutment artefact, and padding is the cure.**

The chain is now complete:

1. Standalone `INVR00` DRC is clean — 0 items, 71 categories. The cell is not
   defective (`docs/invr00-standalone-drc.md`).
2. All three violations sat at an identical offset inside the cell frame
   (Δx = 0.00, Δy = +17.35 / +20.70), i.e. one structural cause reproduced at three
   `NND200`↔`INVR00` seams.
3. Forcing a gap at placement removes them entirely.

The `999:0` waiver layer is capped at 2 polygons, so at 3 violations waiving was
unavailable in principle. That argument is now moot: there is nothing to waive.

## 4. What got worse, and why it is not a density problem

Via-to-poly went **6 → 8**. Across the three runs the count is 0, 6, 8 at densities
0.45, 0.05, 0.20 — **not monotonic**, so it does not track density. Padding spreads
cells sideways, which lengthens the over-cell wires that carry the offending vias.

The underlying cause is unchanged and is structural: `detailed_route` checks the
**LEF abstract, and the abstract contains no poly**. The router cannot see what it is
violating, which is why `drc.rpt` is 0 bytes and the signoff deck still finds
problems. Both statements are true about different views of the same layout.

### The 8 items are 5 distinct vias

Parsing the edge-pairs, three vias are reported **twice** — once per side — at an
x-separation of exactly **1.5 µm, the via width**:

| via | edges reported | gap to poly |
|---|---|---|
| ~641.5, 592 | 640.8 and 642.3 | 0.05 and 0.25 µm |
| ~1207, 1150 | 1206.3 and 1207.8 | 0.05 and 0.25 µm |
| ~676.6, 1454 | 675.9 and 677.4 | 0.05 and 0.25 µm |
| 462.9, 999 | one edge | 0.15 µm |
| 1320.9, 696 | one edge | 0.15 µm |

Required spacing is 1.0 µm; the worst case is 0.05 µm, twenty times under.

**Do not quote the item count as a defect count.** Eight report entries are five
physical problems. The same caution applies to the earlier 6-item result, which has
not been re-parsed this way.

All five sit between 462 and 1321 µm. The 0.05-density set spanned 876 to 2289 µm —
the higher density pulled the logic into a tighter cluster, as intended.

## 5. Timing has now not moved across four configurations

Setup `a[1]` → `zero` at **11.61 ns, slack +88.39 MET**, hold `b[7]` → `carry` at
**+0.78 MET**, through the same ten instances with the same per-gate delays, at:

- 1 mm die, density 0.45
- 4 mm die, density 0.05
- 4 mm die, density 0.20 with padding

Die area changed by 16×, density by 9×, and padding went from off to on. The STA
output has never moved by one picosecond.

This is the cell-delay-only caveat as a **measurement** rather than a disclaimer. The
SPEF is read, but the OpenRCX rule deck for this process yields zero capacitance on
every net, so wire length is invisible to the timer. Any frequency quoted from these
runs — 11.61 ns, about 86 MHz — is cell delay only, typical corner, 5 V, 25 °C.

## 6. Process note: a signoff script has no run-tag hook

`cdl_gds_script.source` **hardcodes the run directory**. There is no tag variable; the
copy on the machine had been hand-edited to `runs/CHIP`. A first signoff attempt
therefore re-verified the previous run and overwrote `5_klayout/lvs_drc/`. The fix was
a derived `cdl_gds_script.pad_d020.source` with every path rewritten.

**Rule: read `<original-file>` out of a KLayout report before reading its counts.**
That line names the GDS actually checked and is the only thing that distinguishes a
fresh result from a re-run of something else.

The accident had one useful side effect: it regenerated the 0.05 signoff from scratch,
and a `diff` of the `<value>` lists against the archived copy is **empty**. Signoff
determinism is confirmed a second time.

## 7. Next on via-to-poly

None of these has been tried:

1. **Routing layer adjustment.** `routing_cp8d.tcl` currently sets
   `set_global_routing_layer_adjustment metal1 0` and `metal2 0` — no derating at all.
   Raising it discourages the router from using tracks over cells. Cheapest untried
   knob.
2. **A routing blockage over cell poly** before `detailed_route`, so the router is
   told about what the abstract hides.
3. **A tighter core area**, so wires stop crossing cells to reach distant pins.
4. **Accept five and fix them by hand** in KLayout, which is normal practice at this
   scale but costs the scripted-flow property.

Options 1 and 3 interact with the boron result and must be re-signed-off, not assumed.
