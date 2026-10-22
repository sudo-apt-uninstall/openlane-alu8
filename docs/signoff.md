# Signoff — KLayout DRC and LVS

**Run date:** 2026-10-22
**Verdict:** **LVS ✅ clean (0 errors)** · **signoff DRC ⚠️ 3 violations**

---

## 1. Router DRC is not signoff DRC

This repository previously reported "router DRC clean" and that statement was
correct but kept being read far too broadly. The two checks are different:

| | router DRC | signoff DRC |
|---|---|---|
| what it checks | the wiring the router itself drew | the full streamed-out GDS |
| cell interiors | **no** — cells are abstract LEF outlines | **yes** — every polygon, flattened |
| cell boundaries | not examined | examined, including abutment seams |
| rule set | routing rules from the tech LEF | the full process rule deck |
| tool | OpenROAD / TritonRoute | KLayout + `cp8d_drc.drc` |
| alu8 result | `drc.rpt` **0 bytes — PASS** | **3 violations — FAIL** |

A design can pass the first and fail the second. alu8 does exactly that.

> **Rule:** never quote `drc.rpt` as "DRC clean" without the word *router*.

---

## 2. LVS — clean

Layout versus schematic **passes with 0 errors**: the routed layout is
electrically equivalent to the synthesised netlist. Every device and every
connection, including the supply hookups, matches.

| artefact | bytes | what it is |
|---|---:|---|
| `alu8.cdl` | 22,347 | source netlist, generated from `alu8_rt_pwr.v` |
| `alu8_extracted.cir` | 42,167 | netlist extracted from the layout |
| `alu8.lvsdb` | 662,694 | the comparison database — **holds the verdict** |

**The input choice matters and is easy to get wrong.** Routing emits two
Verilog netlists:

- `alu8_rt_pwr.v` (46,062 B) — **with** `VDD` / `GROUND` pins → **use this for LVS**
- `alu8_rt_sim.v` (18,144 B) — **without** supply pins → for gate-level simulation

Feeding `_rt_sim.v` to LVS is the classic own-goal on this flow: the extracted
layout has power connectivity, the source netlist does not, and every supply net
mismatches. `cdl_gds_script.source` calls `verilog2spice.py` with
`-pos_pwr VDD -neg_pwr GROUND`, so the correct file is used.

### There is no pass/fail text report

The verdict exists **only inside `alu8.lvsdb`**. Nothing in the flow prints
"LVS matched" to a log or a file. It has to be opened in
**KLayout → Tools → Netlist Browser**.

That is a genuine usability trap: the database sat on disk for roughly ten
hours while the LVS status was treated as unknown — and it had been a clean
pass the whole time.

---

## 3. Signoff DRC — 3 violations

```
$ grep -c '<item>' scl_drc.txt
3

$ grep -o '<category>[^<]*</category>' scl_drc.txt | sort | uniq -c
      3 '6.1.1 and 6.1.2 : Minimum Boron width violations =  3.4um'
```

One category, three instances. Every edge-pair spans **3.35 µm** against a
**3.4 µm** minimum — **50 nm short**, three times over. This is a sliver, not a
structural failure.

| # | edge-pair (µm) | span |
|---|---|---|
| 1 | `(468,169.45;467.419,169.45)` \| `(468,172.8;468.581,172.8)` | 3.35 |
| 2 | `(643.5,372.25;642.919,372.25)` \| `(643.5,375.6;644.081,375.6)` | 3.35 |
| 3 | `(744.9,169.45;744.319,169.45)` \| `(744.9,172.8;745.481,172.8)` | 3.35 |

### 3.1 Mapping violations back to instances

Each coordinate was matched against the component list in `alu8_rt.def`:

| violation site | instance | cell | placed at |
|---|---|---|---|
| 468.0, 169.45 | `_281_` | **INVR00** | 468.0, 152.1 |
| 643.5, 372.25 | `_252_` | **INVR00** | 643.5, 354.9 |
| 744.9, 169.45 | `_257_` | **INVR00** | 744.9, 152.1 |

**All three are INVR00**, the library's basic inverter — 20 of which are placed
in this design.

### 3.2 The discriminating pattern

Every INVR00 instance was scanned with its left and right row neighbours:

| INVR00 x | row y | left neighbour | Δx | DRC |
|---:|---:|---|---:|:--:|
| 468.0 | 152.1 | NND200 @ 452.4 | **15.6** | ❌ |
| 744.9 | 152.1 | NND200 @ 729.3 | **15.6** | ❌ |
| 643.5 | 354.9 | NND200 @ 627.9 | **15.6** | ❌ |
| 479.7 | 101.4 | NOR200 @ 464.1 | 15.6 | ✅ |
| 647.4 | 101.4 | NND200 @ 612.3 | 35.1 | ✅ |
| 495.3 | 304.2 | NND200 @ 475.8 | 19.5 | ✅ |
| 265.2 | 304.2 | NND200 @ 241.8 | 23.4 | ✅ |
| 167.7 | 456.3 | INVR00 @ 156.0 | 11.7 | ✅ |

**Working hypothesis:** the three failures are the only **hard-abutted
NND200 → INVR00** pairs — Δx = 15.6 µm with no intervening gap. The boron notch
forms at that specific cell-to-cell seam.

Note the control case: the INVR00 at x = 479.7 is *also* at Δx = 15.6, but its
left neighbour is a **NOR200**, and it passes. So the hypothesis is about the
NND200/INVR00 seam specifically, **not** about spacing alone.

**This hypothesis is unconfirmed.** See §3.4 for the experiment that settles it.

### 3.3 A corroborating lead in the SCL configuration

`runs/RUN.bak/config.tcl` carries two variables that are **not** OpenLane
defaults — they were authored by SCL:

```tcl
set ::env(DRC_EXCLUDE_CELL_LIST)     "inv0d0"
set ::env(DRC_EXCLUDE_CELL_LIST_OPT) "INVR01"
```

SCL excluded an **INVR-family inverter** from DRC. Every one of our three
violations is on **INVR00**. That raises a real possibility that this is a
**known library defect**, not something the placement caused.

⚠️ Caveat: those variables belong to OpenLane's *native* Magic/KLayout stages,
which this SCL flow bypasses entirely (it uses raw `run_openroad_script`
calls). So the exclusion was most likely never actually applied here. **The
intent is the signal, not the mechanism.**

### 3.4 The deciding experiment

Run the process deck against **INVR00 alone**, straight out of the library GDS:

```bash
klayout -b -r <cp8d_drc.drc> \
  -rd top_cell=INVR00 \
  -rd input=<libs.ref/digital_cp8d/gds/std_cells_cp8d.gds> \
  -rd report=/tmp/invr00.xml
grep -c '<item>' /tmp/invr00.xml
```

- **0 items** → the cell is fine in isolation → the notch is created by
  **abutment** → fix in placement (lower `PL_TARGET_DENSITY` so no NND200 hard
  abuts an INVR00, then re-run from placement).
- **> 0 items** → **PDK library defect**, corroborated by §3.3.

LVS passing makes this sharper: connectivity is provably correct, so the three
violations are **purely geometric** — either inside the cell or at its seam.
There is no third possibility.

### 3.5 The waiver route is not available

The CP8D deck carries an undocumented waiver layer, `999:0`, subtracted from
every process layer. It is **hard-capped at 2 polygons** — the deck raises and
aborts beyond that. With **3** violations, waiving is impossible even in
principle. At least one must be genuinely fixed, or genuinely proven to be a
library defect.

---

## 4. How signoff is actually run — manually

**There is no Makefile.** The only driver is
`5_klayout/cdl_gds_script.source` (2,755 B), and what it does is:

1. `source cp8d_pdk_env_setting.source` — PDK environment
2. `verilog2spice.py` : `alu8_rt_pwr.v` → `lvs_drc/alu8.cdl`
   (`-pos_pwr VDD -neg_pwr GROUND -delimiter`)
3. `def2gds.py` via `klayout -b -zz` : `alu8_rt.def` → `lvs_drc/alu8.gds`
4. `klayout -e alu8.gds &` — **opens the GUI**

It runs **neither DRC nor LVS**. Both were executed by hand inside the KLayout
GUI. That is why an `alu8.lvsdb` exists with no accompanying report, and why
signoff is **not reproducible** in the way the flow itself now is.

**Open gap:** a `signoff.sh` that performs GDS → DRC → LVS headless and prints
both counts, so the full chain becomes `source run_all.tcl` + `./signoff.sh`.

### 4.1 Signoff artefacts go stale silently

`run_all.tcl` ends at STA — **it has no GDS streamout stage**. So after a
re-run, everything under `5_klayout/lvs_drc/` still describes the *previous*
layout:

| file | timestamp | describes |
|---|---|---|
| `runs/RUN/results/routing/alu8_rt.def` | 22 Oct 21:07 | the current run |
| `5_klayout/lvs_drc/alu8.gds` | 22 Oct 06:19 | previous run |
| `5_klayout/lvs_drc/scl_drc.txt` | 22 Oct 05:48 | previous run |
| `5_klayout/lvs_drc/alu8.lvsdb` | 22 Oct 05:48 | previous run |

Because the flow is deterministic the content is equivalent, but the timestamps
make that an argument rather than a measurement. Regenerate the CDL and GDS
before quoting signoff results against any particular run.

---

## 5. Current signoff scorecard

| check | result |
|---|---|
| router DRC | ✅ 0 (`drc.rpt` 0 bytes) |
| setup timing | ✅ +88.39 ns slack MET |
| hold timing | ✅ +0.78 ns slack MET |
| **LVS** | ✅ **0 errors** |
| signoff DRC | ⚠️ 3 boron-width violations, all INVR00 |
| gate-level simulation | ⬜ not run |

One isolated geometric issue on one cell type. Nothing else in signoff is
outstanding.
