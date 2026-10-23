# Caveats for taking a design to tapeout on the SCL Open PDK

Written 2026-10-23, at the point where the `alu8` work is being parked. Everything
below was either **read out of the shipped kit**, **read in one of the five SCL
documents**, or **measured on a run of this design**. Where something is inferred
rather than measured it says so.

Two PDKs are in scope: **CP8D** (0.8 µm digital) and **C1D** (1.2 µm). The work
described here used CP8D.

The headline is not that the PDK is unusable. A full RTL-to-routed-GDS flow ran, LVS
matched, and signoff DRC reached zero on one rule class after one targeted fix. The
caveats are about the distance between *that* and an actual submittable tapeout.

---

## A. Data defects in the kit — wrong numbers, not missing ones

These are the dangerous category, because the tools accept them and produce confident
output.

### A1. The RC extraction decks are empty

| RC source | CP8D 0.8 µm | C1D 1.2 µm |
|---|---|---|
| OpenRCX resistance | absent (all zero) | absent (all zero) |
| OpenRCX capacitance | **absent (all zero)** | present, sparse |

`scl_cp8d/libs.tech/openrcx/scl800.rcx.lib` is 2,763 B and
`sclc1d/libs.tech/openrcx/scl_c1d.rcx.lib` is 3,166 B — the same template, with widths
correctly scaled per process, so the values were dropped during packaging rather than
never computed. Every `RESOVER` row in both is `0 0`. C1D additionally has two zero
holes between non-zero neighbours (`M1 UNDER 2` at d=3, `M2 OVER 0` at d=8.5).

**Consequence:** the SPEF produced by the flow carries **connectivity only**. On this
design every `*D_NET` capacitance was 0. Any frequency you quote is **cell delay
only**.

### A2. The CP8D tech LEF capacitance is about 1000× too large

`CPERSQDIST` in `tech_cp8d.lef`: metal1 **0.027**, metal2 **0.011**.
The same field in C1D's `tech_c1d.lef`: **0.000027**, **0.0000156**.

Same mantissa, `e-3` dropped. Confirmed four independent ways:

1. The sister PDK's value is three decades smaller.
2. Oxide physics: ε_ox/t_ox = 3.45e-11 / 1e-6 = **3.45e-5 pF/µm²**. C1D's 2.7e-5
   matches; CP8D's 0.027 = 27 fF/µm² is physically impossible.
3. SCL's own CP8D document §5.4 p.15 quotes INVR00 gate capacitance 0.00863283 pF and
   a routing capacitance of **0.00595 pF**. At the corrected 0.246 fF/µm that is
   24.2 µm of metal1 — an ordinary net. At the declared value it is 0.13 µm, absurd.
4. The 175 Å gate oxide stated in the analog document.

**Consequence, measured:** `set_wire_rc -layer metal1` on this design produced an
arrival time of **352,200,736 ns**, a WNS of **−352200640**, and *negative* cell
delays (−44427.80 on an AND200). The topology stayed correct, so it is purely an RC
magnitude fault.

**Workaround:** `set_wire_rc -resistance 4.12e-5 -capacitance 2.46e-4` with
`set_cmd_units` — i.e. read the declared 0.027 as fF/µm² rather than pF/µm². C1D's
`-layer metal1` is legitimate as shipped.

**Useful sanity bound:** ~0.006 pF ≈ 24 µm of metal1. Judge any parasitics estimate
against it.

### A3. Config files contain copy-paste errors and unreliable comments

In the shipped CP8D config: `CLOCK_PERIOD 100` with a comment saying "10.0";
`SYNTH_MIN_BUF_PORT BUFF00` commented as `CDRI01`; and `inv0d0` in both
`NO_SYNTH_CELL_LIST` and `DRC_EXCLUDE_CELL_LIST` — a cell name from a different PDK
entirely, since SCL's inverters are `INVR00`..`INVR05`. **No cell is actually excluded
from synthesis** despite the config appearing to exclude one.

**Rule: trust values and the LEF, never the comments.**

### A4. The LEF SITE height and the drawn cell height disagree by 7 µm

`SITE CORE` is `3.900 BY 25.350`. Every cell's drawn metal1 spans
Y −3.500 .. 28.850 = **32.35 µm**, because the VDD and GROUND rails overhang 3.5 µm
top and bottom. Both numbers are real measurements of the same cell: 25.35 is the
abutment box, 32.35 is the full drawn extent.

`initialize_floorplan -site CORE` builds rows at **25.35**, so rows overlap, and SCL's
own `floorplan_cp8d.tcl` compensates by **destroying every odd row** with
`odb::dbRow_destroy`. That is where the 50.7 µm row pitch comes from: 25.35 × 2.

**Consequence: 18.35 µm of every 50.70 µm row is dead space — 36 % of the core is
unusable.** Harmless at the ~1.2 % utilisation of this design; it would invalidate any
utilisation figure for a dense one.

⚠️ **Do not "fix" `PLACE_SITE_HEIGHT` to 25.35.** If rows are not flipped, a 25.35
pitch puts one row's VDD (17.700..28.850) across the next row's GROUND
(21.850..32.200) — overlap 21.850..28.850, a **direct VDD-to-GROUND short**. Whether
25.35 with alternating orientation and shared rails would work has never been tested.
The 50.7 arrangement is the one that produced clean DRC and matched LVS.

---

## B. Artefacts the submission requires that the PDK does not contain

These block submission regardless of how good the design is.

### B1. No antenna rule deck

SCL requires a *"DRC/**Antenna** clean GDSII"*. Grepping the entire CP8D tree —
**102 directories, 264 files** — and all five SCL PDFs for `antenna` returns **zero
hits**.

You can be fully DRC-clean and still un-submittable, **with no way to self-check**.
Whether a 2-metal 0.8 µm process is antenna-exempt is a reasonable question to ask SCL
or NIELIT, but it must be asked rather than assumed.

### B2. No seal ring

The MPW page states the seal ring and its readme *"are given in the PDK"*. Tree grep
for `seal`, `ring`, `revision`, `silicon` returns **zero hits**.

⚠️ `CORNER.gds` and `corner_cp8d.lef` **do** ship — those are pad-ring **corner
cells**, not a seal ring. They are easy to mistake for one. (Measured aside: the 4 mm
frame instantiates no corner cells at all — 41 instances = 40 pads + a logo.)

### B3. No tapeout submission form

Named four times across the MPW page and the procedure document. It carries the
compliance checklist SCL inspects against, and the division contacts needed to obtain
a silicon number. Never seen. It gates both ends of the process.

### B4. `filler_placement.tcl` is mandated by the README and was never shipped

README step 27, note 1, verbatim: *"If your design is a purely combinational circuit or
a ring oscillator, skip the `cts_cp8d.tcl` script and run `filler_placement.tcl`
instead to avoid TritonCTS errors."*

**No such file exists anywhere in the PDK.** `3_src` contains exactly ten scripts, and
`script_openlane.tcl` calls `cts_cp8d.tcl` unconditionally. For a combinational design
you must write the filler step yourself. (Ours is 937 B.)

### B5. There is no sample design

`sample_project_files_cp8d/1_RTL/` is **empty**, as are `4A_synthesis_netlist/` and
both testbench folders. The "sample project" is a scaffold: nine PnR Tcl scripts, a
`config.json`, a `pin_order.cfg`, and driver scripts. **"Run the vendor's example as a
known-good reference" is not available.** The first flow run has to use your own RTL,
so a deliberately tiny smoke design is worth building first.

### B6. Bonding is fixed one-to-one with the pin-out

Bonding diagrams and chip-on-board footprints come from SCL via the portal. Because
bonding is 1:1 with pad order, **the pad order on the frame determines the package
pinout**, with no bond-wire freedom to correct it later. Freeze pad order only after
you have those diagrams.

---

## C. Flow and script defects

### C1. The run tag is inert — every script hardcodes `runs/RUN`

`yosys_script.tcl`, `floorplan_cp8d.tcl`, `routing_cp8d.tcl` and
`cdl_gds_script.source` all write to `$DESIGN_DIR/runs/RUN/...` literally.

So `./flow.tcl -tag CHIP` creates `runs/CHIP` for OpenLane's bookkeeping and **every
stage writes into `runs/RUN` anyway**, silently overwriting whatever is there. The
first attempt with `-tag CHIP` tripped a stage check because it was looking in a
directory nothing ever writes to.

**Procedure: move `runs/RUN` aside first, run as `-tag RUN`, rename afterwards.**
`-overwrite` is only safe because of that move.

### C2. Config variables that are read and never used

Because `run_openroad_script` bypasses OpenLane's native steps, **every variable those
steps would have consumed is dead**. Two cases found, both only when something else
broke:

- **`FP_PIN_ORDER_CFG`** — there is no `place_pins` call in `floorplan_cp8d.tcl` at
  all. The only one is in `routing_cp8d.tcl`, with no `-group_pins` and no
  constraints, and it runs **after** placement. So placement sees no pin locations,
  and the router assigns them heuristically at the end. For a pad-limited die this is
  backwards: cells cannot be pulled toward their pads, and any alignment with the pad
  openings is accidental.
- **`GPL_CELL_PADDING` / `DPL_CELL_PADDING`** — `set_placement_padding` is never
  called. The config set 40 and 20; neither reached the placer.

**The general caveat: in this flow the config file is a list of intentions, not a
description of the run.** The only way to know which is which is to read the scripts.

### C3. The signoff driver has no run-tag hook and clobbers its own report

`cdl_gds_script.source` hardcodes the run directory. It also **re-sources the PDK
environment**, resetting `PDK_ROOT` to a different tree than the one `sclenv` set.

Worse: the KLayout DRC deck writes `./scl_drc.txt` **relative to the current working
directory with no `-rd` override**. Running it from inside the PDK tree once
**overwrote the PDK's own `scl_drc.txt`**. Two designs checked from one directory
silently clobber each other.

**Rule: always read `<original-file>`, `<top-cell>` and `<generator>` out of a KLayout
report before believing its counts.** All three are in the header and all three can
quietly be wrong.

### C4. Signoff is manual and is not part of the flow

`cdl_gds_script.source` runs `verilog2spice.py` → CDL, `def2gds.py` → GDS, then
`klayout -e`, which **opens the GUI**. It runs neither DRC nor LVS. There is no
makefile. Both checks were done by hand, which is why there are no report files and no
reproducibility until you write the batch driver yourself.

There is also **no GDS streamout inside the flow**, so the GDS and all signoff
artefacts go stale after every re-run until regenerated by hand.

### C5. C1D cannot be driven end-to-end as shipped

C1D ships **7 flow scripts against CP8D's 10** — no `script_openlane.tcl`, no
`yosys_script.tcl`, no RCX script. All three of its `config.tcl` files are
byte-identical 12-line stubs with a broken `PDK_ROOT` and `LIB_SYNTH` pointing at the
**pad** library while the core library sits beside it. The shipped comments are literal
placeholders.

Also: the C1D pad set shares **no cell names** with CP8D except `PVDD01`/`PVSS01`, so
pad work does not port between the two PDKs.

**CP8D is the arm that works.** The asymmetry is consistent: C1D has the better
documentation and correct RC data but a stub config; CP8D has a working config and no
flow annexure and a null RCX deck.

---

## D. What the verification decks do not check

A clean run is weaker evidence than it looks.

### D1. Three design rules are not implemented and must be checked by hand

1. Metal-1 **necking length** 4 µm.
2. Max metal-1 **bus width** over a single diffusion contact, 12 µm.
3. **Max metal-1 / metal-2 width 25 µm × 25 µm (rule 10.5.1).**

The third is the dangerous one: **wide power straps pass DRC and are still
non-compliant**, surfacing only at SCL incoming inspection. That is one lost shuttle.

⚠️ The analog document's own "DRC does not check" prose is **stale** — it is dated
13/03/26 while the deck `cp8d_drc.drc` is **v1.1, 16/09/2026** and implements most of
what the prose says is unchecked. **To answer "is this checked?", read the deck, never
the PDF.** The deck is 24,627 B, sha `7634e4ab5a450fe28211e039aa798e0180111092`, and
is byte-identical in the analog and digital arms — one deck governs both flows.

### D2. Three of eight ERC guidelines produce no output

- **G1** (well contacts every 50 µm) — computed, never written out.
- **G2** (gates tied to supply) — computed, never written out.
- **G4** (floating gates) — **dead logic**: `connected_poly.not(poly)` on a set already
  inside poly is always empty, so it can never fire.

**A clean ERC run is not evidence of "no floating gates" or "no missing well
contacts".** Those must be argued another way.

The binding ERC number is not the headline one: well contacts every 50 µm across a
well, but **every PMOS gate needs a well or substrate contact within 25 µm**.

### D3. The router's DRC and the signoff DRC disagree, legitimately

`detailed_route` checks the **LEF abstract, and the abstract contains no poly**. So the
router reports `drc.rpt` at 0 bytes — genuinely clean on what it can see — while the
signoff deck finds via-over-poly violations. Both are true about different views of the
same layout.

**Router DRC clean is not signoff DRC clean.** On this design that gap was 0 vs 8
reported items.

### D4. A report item count is not a defect count

In our final run the deck reported **8** items in one category. Parsing the
edge-pairs, three vias were each reported **twice** — once per side, at an
x-separation of exactly 1.5 µm, the via width. **Eight report entries were five
physical defects.**

### D5. There is an undocumented waiver layer, and it is nearly useless

Layer `999:0` is subtracted from every process layer, and is **hard-capped at two
polygons** — the deck raises and aborts beyond that. It appears in none of the five
PDFs. With three violations, waiving was unavailable in principle.

### D6. The kit is marked confidential inside a public download

The DRC deck header marks the kit **CONFIDENTIAL / NDA, no redistribution** — inside a
publicly downloadable "open source" PDK. Whatever the intent, **do not commit PDK
bytes** (`.lib`, `.lef`, cell GDS, rule decks) to a public repository. Your own flow
scripts, configs and run outputs are fine.

---

## E. Signoff-quality timing is not achievable on this PDK

Three independent reasons, all of which must be stated together whenever a frequency
is quoted:

1. **No parasitics** (A1, A2) — the SPEF has zero capacitance on every net.
2. **Typical corner only.** CP8D §5.3 gives TYP **5 V / 25 °C**, WORST **4.5 V /
   85 °C**, BEST **5.5 V / −20 °C** — but **the digital kit ships no worst-case
   library**. The flow reads `cp8d_core_typ.lib`. Worst-case signoff is impossible.
3. **`CLOCK_PERIOD` never reaches synthesis.** `abc -liberty` is called with no `-D`
   and no SDC, so ABC maps for **area**. The period only feeds the STA script's
   `create_clock`. Re-running the whole flow "to get timing-driven synthesis" buys
   nothing.

**How strong is reason 1? Measured.** The same design was run at 1 mm die / density
0.45, 4 mm die / density 0.05, and 4 mm die / density 0.20 with cell padding. Die area
changed by 16×, density by 9×, padding off to on. The STA reported setup **11.61 ns,
slack +88.39 MET** and hold **+0.78 MET** through the same ten instances with the same
per-gate delays, to the picosecond, **every time**. Wire length is invisible to the
timer.

**Mandatory phrasing: "about 86 MHz — cell delay only, interconnect parasitics not
modelled by the PDK, typical corner 5 V / 25 °C."**

Devices marked `*` in the documentation are **not offered for PEX extraction** at all.

---

## F. Toolchain constraints

### F1. KLayout signoff is non-negotiable

SCL ships LEF, Liberty ×3 corners, GDS, CDL, Verilog models, KLayout DRC/LVS decks,
Magic tech, xschem views, and the OpenRCX deck.

It does **not** ship a Virtuoso techfile or display resource, a QRC tech file,
Pegasus/PVS/Assura decks, OpenAccess libraries, or a `cds.lib`.

For a standard-cell digital design most of those are irrelevant rather than missing —
layout comes from OpenROAD, verification from Icarus or Xcelium. Only two gaps touch a
digital flow, and both are covered: signoff DRC/LVS goes to **KLayout**, extraction to
**OpenRCX**.

The decider: **submission requires a DRC report from SCL's own KLayout deck**, named
`Silicon no._Design Name_Date_Version_drc.txt`. Genus, Innovus, Tempus, Conformal and
Xcelium are all usable for synthesis, PnR and STA cross-checks, but they cannot produce
the submitted signoff report. Innovus extraction is limited to LEF-derived R/C, which
inherits defect A2.

### F2. Environment collisions

The SCL environment script **refuses to load** if `CADENCE_ROOT` and `DDIROOT` are set
— the two define conflicting `PDK_ROOT` values. It is also a launcher, not a sourceable
file (`exec bash --rcfile`), so `$PDK_ROOT` expands to `//` in a shell you were already
in.

`cdl_gds_script.source` **re-sources a different PDK environment** and silently
overrides `PDK_ROOT`, which is how a report can end up generated against a different
tree than the one you built with.

Deck paths carry a `tech/` level that is easy to miss:
`$KLAYOUT_PATH/tech/drc/drc.lydrc`, not `$KLAYOUT_PATH/drc/`.

### F3. A LibreLane port is not a drop-in

CP8D already ships the `open_pdks` tree LibreLane expects, so step one is a copy or
symlink rather than authoring configs. But: the `RUN_*` step toggles have no
equivalent; `HOOK_POST_DETAILED_ROUTING "detailed_route -allow_offgrid_pins true"`
needs a custom Python step because SCL's pins really are off-grid; LibreLane does not
auto-scale PDN offsets and pitches for a 2-metal process the way OpenLane 1 did; and
the site-height compensation in D/A4 lives in a *design-level* floorplan script, so a
second and more invasive custom step is needed. **C1D should not be attempted at all**
until its config is authored.

### F4. Two metals is a real constraint, not a footnote

`tech_cp8d.lef` declares only diffusion, poly, contact, metal1, via, metal2. The PDN
rail and the horizontal straps both sit on **metal1 alongside signal routing**.

⚠️ **Never enable vertical metal2 power stripes.** Signals are pinned to
`metal1-metal2`, so metal2 straps would consume the only vertical signal resource
there is.

---

## G. What actually worked, so the list is not read as a verdict

- RTL → routed GDS completed on CP8D for two designs (a counter and this ALU).
- **LVS matched** at every die size and density tried.
- Router DRC was clean (0-byte `drc.rpt`) in every run.
- The flow is **scripted and byte-for-byte deterministic**, proven through signoff: a
  re-run reproduced `alu8_rt.def`, `_rt_sim.v`, `_rt_pwr.v` and `drc.rpt` exactly, and
  a regenerated DRC report reported the same items at the same coordinates.
- 8 of the 10 stock `3_src` scripts are byte-identical to SCL's upstream. The two that
  differ are exactly the two a real design must touch: the Yosys script (top module and
  RTL name) and the STA script (design SDC).
- **The one signoff DRC class we attacked went to zero.** Three boron-width violations
  were traced to cell abutment — a standalone DRC on the cell itself was clean across
  all 71 rule categories — and adding one site of placement padding removed them
  entirely.

The remaining open item on this design is via-over-poly, which is D3: the router cannot
see poly in the abstract. Five real vias sit 0.05 to 0.25 µm from poly against a 1.0 µm
rule. Untried levers are routing-layer derating (currently 0 for both metals), an
explicit routing blockage over cell poly, or a tighter core.

---

## Summary — the five that would cost a shuttle

1. **No antenna deck**, against an antenna-clean submission requirement (B1).
2. **No seal ring**, despite documentation saying it ships (B2).
3. **Max metal width is a real rule the deck does not check** — wide straps pass DRC
   and fail inspection (D1).
4. **The LEF capacitance is 1000× wrong**, and using it produces confident nonsense
   rather than an error (A2).
5. **Config variables that are silently dead**, so the floorplan you designed is not
   necessarily the floorplan you got (C2).
