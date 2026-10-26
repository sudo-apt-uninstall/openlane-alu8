# 8-bit ALU on the SCL CP8D 0.8 µm PDK

### An RTL-to-GDSII study using OpenLane / OpenROAD

**Deepesh J** — VLSI Physical Design internship, Wipro
Design partner on the trial: Sai Darshan
Target technology: SCL Mohali CP8D, 0.8 µm, 2 metal layers
Tooling: OpenLane v1.0.2 (`ff5509f6`), OpenROAD, Yosys, KLayout

> Scope note: this is an individual learning exercise to gain full-flow exposure on a
> real foundry PDK. It is not a Wipro deliverable and not a tape-out submission.

---

## 1. Why this exercise

Most PD training stops at "run the tool and look at the GUI." The objective here was the
opposite: take a small design all the way from RTL to a streamed-out GDS on a **real
foundry PDK**, and then actually sign it off — so that every number quoted has a file
behind it.

Three things made it worth doing:

1. **CP8D is a 2-metal, 0.8 µm kit.** No deep-metal escape hatch, no assist layers. Every
   routing decision is visible.
2. **The design is purely combinational.** OpenLane's default flow assumes a clock. Making
   it work without one forced a real understanding of which stage does what, instead of
   trusting `flow.tcl`.
3. **Sign-off is manual in this kit.** SCL ships no automated DRC/LVS driver, so the
   results had to be produced and interpreted by hand in KLayout.

---

## 2. The design

A straightforward 8-bit ALU: two 8-bit operands, a 3-bit opcode, an 8-bit result plus
`zero` and `carry` status flags. 29 I/O pins in total.

| Property | Value |
|---|---|
| Inputs | `a[7:0]`, `b[7:0]`, `op[2:0]` |
| Outputs | `result[7:0]`, `zero`, `carry` |
| Sequential elements | **none** — fully combinational |
| Synthesised cell count | **210 CP8D standard cells** |
| Dominant structure | 28 × `MX2100` output mux tree |
| Adder | mapped to `ADNR00`, not `ADR100` |

The adder choice is itself a finding. Yosys calls `abc -liberty` with no `-D` and no SDC,
so **ABC maps for area, never for delay**. `CLOCK_PERIOD` in the config never reaches
synthesis at all — it only feeds the STA script. The "mystery" of the slower adder cell
turned out to be an area-mode decision, not a library gap.

---

## 3. The flow as actually run

```
RTL (alu8.v)
  → Yosys synthesis            210 cells
  → Floorplan                  1 mm die, 16 rows @ 50.7 µm pitch, ~33 % occupancy
  → Power distribution         SPECIALNETS 2, metal1 7 µm followpins
  → Global + detailed place
  → Filler insertion           (hand-written substitute for CTS)
  → Global + detailed route    drc.rpt = 0 bytes
  → Parasitic extraction       SPEF written
  → Static timing analysis     11.61 ns
  → GDS streamout + KLayout DRC / LVS   (manual)
```

CTS is skipped deliberately — `RUN_CTS false`. There is no clock to build a tree for, and
`cts_cp8d.tcl` would fail on `[get_ports clk]`.

**The entire flow is now a single script**, `flow/run_all.tcl`, which runs all eight stages
and calls a `must` check after each one that errors out on a missing or zero-byte artefact.
That turned "did the stage work?" from a manual eyeball into an automatic gate.

---

## 4. Seven input-side changes — the only irreplaceable work

Everything downstream is regenerable. A full re-run reproduced every output byte for byte.
These seven edits are what actually constitute the port:

| # | File | Change | Why |
|---|---|---|---|
| 1 | `1_RTL/alu8.v` | `.sv` renamed to `.v` | `yosys_script.tcl` hardcodes `$DESIGN_NAME.v`. The extension now lies about the content — SystemVerilog in a `.v` file. |
| 2 | `3_src/yosys_script.tcl` | added `-sv` to `read_verilog` | so the SystemVerilog actually parses |
| 3 | `config.json` | `CLOCK_PORT ""`, `CLOCK_NET ""`, `RUN_CTS false` | tells the flow there is no clock |
| 4 | `pin_order.cfg` | 29 pins grouped by edge | intended pad-side alignment |
| 5 | `3_src/run_sta.tcl` | **virtual clock** replaces `[get_ports clk]` | a combinational design still needs a timing reference to report against |
| 6 | `3_src/fill_cp8d.tcl` | **hand-written, 937 B** | SCL's own README mandates the fill step but never ships the file |
| 7 | `5_klayout/cdl_gds_script.source` | template instantiated for `alu8` | drives CDL + GDS generation |

**Provenance was verified, not assumed.** Hashing all ten stock scripts with
`git hash-object` showed **8 of 10 byte-identical to the stock CP8D kit**; the only two
that differ are `run_sta.tcl` and `yosys_script.tcl` — exactly the two a real design must
touch. So every result below is provably the output of unmodified foundry scripts.

---

## 5. Results

### 5.1 Timing

| Metric | Value |
|---|---|
| Critical path | `a[1]` → `zero`, 10 logic levels |
| Setup arrival | **11.61 ns** ⇒ **≈ 86 MHz** |
| Setup slack | +88.39 MET (against a 100 ns placeholder period) |
| Hold slack | +0.78 MET |
| Corner | typical only — 5 V, 25 °C |

> **Mandatory qualifier, used every time this number is quoted:** *cell delay only —
> interconnect parasitics are not modelled by this PDK.* The SPEF is read, but every
> `*D_NET` capacitance in it is zero; the PDK's RC rule deck is null. This is a property
> of the kit, not of the run.

For comparison, an 8-bit counter on the same kit closed at 7.93 ns ≈ 120 MHz with 30 cells.

### 5.2 Physical and verification

| Check | Result |
|---|---|
| Router DRC (`drc.rpt`) | **0 bytes — clean** |
| LVS (KLayout) | **"Congratulations! Netlists match." — 0 errors** |
| Sign-off DRC (KLayout, full deck) | **not clean** — see §6 |

Router DRC and sign-off DRC disagreeing is not a contradiction: they examine different
views of the same database. §6.2 explains exactly why.

### 5.3 The routed layout

![Routed GDS](images/GDS-image.png)

---

## 6. The interesting part: sign-off DRC

Three configurations were run. The sign-off result changed each time, and not in the
direction expected.

| | 1 mm die, density 0.45 | 4 mm die, density 0.05 | **4 mm, density 0.20 + cell padding** |
|---|---|---|---|
| Boron width `6.1.1/6.1.2` | 3 | 2 | **0** ✅ |
| Via-to-poly `9.4.1` | 0 | 6 | **8** 🔴 |
| LVS | match | match | **match** |
| Router `drc.rpt` | 0 | 0 | **0** |
| Routed DEF size | 319,149 B | 727,713 B | 721,360 B |
| Filler cells | 356 | 2,214 | 2,197 |
| Setup / hold | 11.61 / +0.78 | identical | identical |

### 6.1 Boron-width violations — diagnosed, then eliminated

All three original violations were the same rule: **minimum boron width 3.4 µm**, each
measuring 3.35 µm — **50 nm short**. They sat on three `INVR00` inverter instances.

The diagnosis was done by arithmetic, not by guessing. Subtracting each instance origin
from its violation coordinate gave **Δx = 0.00 and Δy = +17.35 / +20.70 in all three
cases, to the decimal**. One structural cause, reproduced identically — not three
coincidences, and not random placement noise.

Two candidate explanations were tested and **both ruled out**:

- *Is the cell itself defective?* A standalone DRC on `INVR00` from the library GDS
  returned **zero items across all 71 rule categories**. The cell is clean.
- *Is it a tap-cell issue?* Ruled out.

What remained: every failing inverter sat **hard-abutted** to an `NND200` with zero gap,
while every passing inverter had a gap. So the violation is created *by the abutment*, not
by either cell alone.

That gave a surgical fix — **cell padding** (`set_placement_padding -global -left 1
-right 1`, one site = 3.9 µm) rather than blunt density reduction. The run confirmed it:
**boron violations went to 0 across all 71 categories.** Padding provably reached the
placer (the placed DEF changed size, 404,259 → 404,121 B).

This also closed a blocker: the PDK's waiver layer `999:0` is hard-capped at 2 polygons,
so 3 violations could never have been waived. At least one had to be genuinely fixed —
and now all of them are.

### 6.2 Via-over-poly — found, explained, still open

The new violations are vias landing over polysilicon with gaps of 0.05–0.5 µm against a
1.0 µm rule. The worst is 20× under.

**Root cause:** `detailed_route` checks the **LEF abstract view, which contains no poly at
all.** At very low utilisation, nets run long distances *across* cell areas, and the router
drops vias on top of polysilicon it structurally cannot see. So `drc.rpt = 0` and six real
violations are both true statements — about different views of the same layout.

One further measurement matters for honest reporting: parsing the edge-pairs in the 8-item
report shows **only 5 distinct vias**. Three are flagged twice (left and right edge,
separated by exactly 1.5 µm = the via width). **An 8-item report is 5 real defects** —
item count is not defect count.

**Conclusion drawn:** high density causes boron abutment; low density causes via-over-poly.
There is **no single knob that fixes both**. The via count does not even track density
monotonically (0.45→0, 0.05→6, 0.20→8), which rules out density as the controlling
variable for that rule.

---

## 7. Findings that generalise beyond this design

These are the results most worth carrying forward to other work on this kit.

**7.1 The timing is provably wire-blind.** The setup path (11.61 ns, `a[1]`→`zero`) and
hold slack (+0.78) are **identical across four configurations** — die area varied 16×,
density 9×, padding off and on. The same ten instances, the same per-gate delays to the
picosecond. Interconnect simply is not in the model. This elevates "cell delay only" from a
disclaimer to a **measurement**.

**7.2 The floorplan deletes half its rows.** The CP8D tech LEF declares a site height of
**25.35 µm while the cells are 32.35 µm tall**, so `initialize_floorplan` builds
overlapping rows. The foundry's own floorplan script works around this by destroying every
alternate row. 25.35 × 2 = **50.70 µm — exactly the observed row pitch.** Consequence:
**18.35 µm of every 50.70 µm row is dead space, 36 % wasted.** Harmless at 1.2 %
utilisation; disqualifying for any density claim.

**7.3 Three config variables are silently dead.** `FP_PIN_ORDER_CFG`, `GPL_CELL_PADDING`
and `DPL_CELL_PADDING` are all read into the environment and **never used**, because the
scripts call OpenROAD directly and bypass OpenLane's native stages that would consume them.
The pin ordering in `pin_order.cfg` was therefore **never applied** — `place_pins` lives in
the *routing* script with no constraints at all, so pins are assigned by router heuristic
*after* placement. Any pad-ring merge must fix this first, since bonding is 1:1 with pinout.

**7.4 `-tag` is a trap.** Every `3_src` script hardcodes `runs/RUN` in its output paths.
Passing `-tag CHIP` creates `runs/CHIP` for OpenLane's bookkeeping while every stage still
writes into `runs/RUN` — silently overwriting it. The safe procedure is to rename the
previous run directory first and always run as `RUN`.

**7.5 Always read a DRC report's header before its counts.** The KLayout deck writes
`scl_drc.txt` relative to the current directory with no override, so two designs checked
from one directory clobber each other. Checking `<original-file>`, `<top-cell>` and
`<generator>` in the header caught one run that silently re-verified the *previous*
configuration.

**7.6 Equal file size proves nothing for GDS.** Two GDS files of identical 435,244-byte
length had different SHAs, with 57 % of bytes differing. Parsing both showed 30 cells,
7,383 elements and an **identical geometry multiset** — only the cell write order differed.
Geometrically identical, file-wise not.

---

## 8. Reproducibility

Determinism was not asserted, it was measured, and it holds **all the way through
sign-off**:

- A full re-run reproduced `alu8_rt.def` (319,149 B), `alu8_rt_sim.v` (18,144 B),
  `alu8_rt_pwr.v` (46,062 B) and `drc.rpt` (0 B) **byte for byte**.
- Re-running sign-off against a freshly streamed GDS produced a genuinely different report
  file that nevertheless reported **the same violations at the same coordinates**.
- An accidental third sign-off repetition produced a byte-empty `diff` against the second.

The useful corollary is uncomfortable and worth stating to any reviewer: **if a re-run is
byte-identical, a re-run can never fix a DRC violation.** Closure requires changing an
input. That is precisely what the padding run did.

---

## 9. Current status and what remains

**Done:** RTL → synthesis → floorplan → PDN → placement → fill → routing → extraction →
STA → GDS → KLayout DRC and LVS, scripted end to end, with a deterministic re-run and a
4 mm chip-scale variant archived alongside the 1 mm run.

**Clean:** router DRC, LVS (netlists match), boron-width DRC after padding.

**Open, with a documented next step for each:**

1. **Via-over-poly, 5 distinct defects.** Cheapest untried lever is
   `set_global_routing_layer_adjustment` — currently 0 for both metals — to push wires off
   cell areas. Alternatives: a routing keepout over cell poly, a tighter core, or hand-fix
   in KLayout.
2. **Gate-level simulation never run.** Both inputs exist (`alu8_rt_sim.v`, `alu8_rt.sdf`).
   This is the only step that would verify the routed netlist *computes correctly*, as
   opposed to being structurally and electrically consistent. Highest-value remaining item.
3. **Pin placement is unconstrained** (see 7.3) — must be fixed before any pad-ring work.
4. **No GDS streamout inside the automated flow**, so layout artefacts go stale after each
   re-run until regenerated by hand.
5. **Wire-RC STA experiment** was run twice and the script subsequently deleted; it must be
   rewritten before that result can be re-examined.

---

## 10. What this exercise demonstrates

- A complete RTL-to-GDSII flow executed on a real foundry PDK, scripted and reproducible.
- Adapting a clock-centric flow to a combinational design — virtual clock, CTS bypass, and
  a hand-written fill step the foundry kit does not supply.
- Physical verification read and interpreted directly: DRC rule numbers, edge-pair
  geometry, violation coordinates, and the difference between router DRC and sign-off DRC.
- Root-causing a DRC failure by coordinate arithmetic, eliminating two candidate causes by
  experiment, and closing it with a targeted fix rather than a blunt parameter sweep.
- A disciplined separation between what was **measured**, what was **inferred**, and what
  remains **unknown** — including retracting earlier conclusions in writing when evidence
  contradicted them.

---

### Supporting documents in this repository

| Document | Contents |
|---|---|
| `docs/engineering-notes.md` | Full status table, open items, corrections to earlier claims |
| `docs/signoff.md` | KLayout DRC/LVS procedure and evidence |
| `docs/padding-run-d020.md` | The padding experiment that eliminated the boron violations |
| `docs/chip-run-4mm.md` | 4 mm chip-scale run |
| `docs/invr00-standalone-drc.md` | Proof the inverter cell itself is DRC-clean |
| `docs/determinism.md` | Byte-identical re-run evidence |
| `docs/flow-notes.md` | Reusable combinational-on-CP8D technique |
| `docs/flow-script-audit.md` | Hash verification of the stock scripts |
| `docs/scl-pdk-caveats.md` | PDK-level issues encountered |
| `docs/failed-runs.md` | Failed and superseded runs, with causes |

> **Acknowledgement:** the SCL CP8D PDK is used under its licence terms. No PDK files —
> libraries, LEFs, rule decks or cell GDS — are redistributed in this repository.
