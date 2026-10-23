# Feasibility: SCL CP8D (0.8 µm) through a Cadence flow

Assessed 2026-10-23. **Revised the same day against the Innovus 25.13 User Guide**
(`sudo-apt-uninstall/artifacts-7` → `rtl_to_gds2/innovus/25.13/ug_pdf/`, chapters 3, 8
and 9). Other evidence: the kit itself (`sudo-apt-uninstall/SCL_0.8-um-PDK`, 102
directories / 264 files), the OpenLane runs in this repository, and the 45 nm Cadence
run in `sudo-apt-uninstall/alu-8bit-private`.

**The question as posed was "up to netlist generation is fine I think, but the goal is
tapeout, and the main deal is PD and PV."**

- **Better than assumed:** it does not stop at the netlist. Genus and Innovus both run,
  through placement, CTS, routing and GDS streamout.
- **Different from assumed, after reading the UG:** Innovus *does* have DRC, and it
  *will* run on this PDK — but it reads its rules from the **tech LEF**, and CP8D's LEF
  contains almost none of the statements it looks for. The result is not a blocked tool;
  it is a tool that **reports clean and means nothing.** That is worse.
- **Unchanged:** foundry-signoff PV in Cadence is impossible and would not be accepted.

---

## 1. What each tool needs, and whether the kit has it

| Tool | Needs | Ships? | Verdict |
|---|---|---|---|
| **Xcelium** | Verilog cell models | ✅ `libs.ref/digital_cp8d/verilog/cp8d.v` | **works** |
| **Genus** | Liberty, optionally LEF | ✅ 6 `.lib` (core+pads × min/typ/max), 3 cell LEF | **works** |
| **Innovus** | tech LEF + cell LEF + Liberty | ✅ `tech_cp8d.lef`, `core/pads/corner_cp8d.lef` | **works, 3 fixes** |
| **Innovus `streamOut`** | cell GDS + layer map | ✅ 3 GDS + `scl_cp8d.map` | **works, map needs translation** |
| **Innovus `verify_drc`** | DRC statements **in the tech LEF** | ⚠️ LEF 5.3 from 2004, almost none present | **runs, checks ~nothing — §3.1** |
| **Innovus `verify_antenna`** | `ANTENNAAREARATIO` + pin antenna fields | ❌ LEF built with antenna **off** | **runs, finds nothing — §3.2** |
| **Innovus `verifyConnectivity`** | the DEF itself | ✅ | **works, genuinely useful** |
| **Tempus** | Liberty + SPEF | ⚠️ Liberty yes; SPEF depends on §2.2 | **depends on extraction** |
| **Conformal** | Liberty + Verilog | ✅ both | **works** |
| **Modus** (DFT) | Liberty with scan cells | ✅ `DFCL11` etc. | **works in principle** |
| **Quantus / QRC** | QRC techfile `.tch` | ❌ not in kit — **but see §2.2** | **replaceable** |
| **Pegasus / PVS / Assura** | foundry rule deck | ❌ not in kit | **impossible** |
| **Virtuoso** | `.tf`, `display.drf`, OA libs | ❌ not in kit | **impossible** |

A filename search of the whole tree for `qrc`, `tch`, `assura`, `pegasus`, `cds.lib`,
`techfile`, `drf`, `virtuoso` and `calibre` returns **zero hits**. The kit was built for
an open-source flow; the parts Cadence can consume (LEF, Liberty, GDS, CDL, Verilog) are
the format-neutral ones.

---

## 2. Physical design in Cadence — feasible, with three fixes

### 2.1 The site-height trap hits Innovus too, and the fix is different

`tech_cp8d.lef` declares `SITE CORE ... SIZE 3.900 BY 25.350 ;` while every cell is drawn
**32.35 µm** tall (rails overhang 3.5 µm each side). SCL's OpenLane floorplan script
works around this by **deleting every odd row** after `initialize_floorplan`.

In Innovus, `floorPlan -site CORE` produces the same overlapping rows and there is no
`odb::dbRow_destroy` equivalent. Two options:

1. **Edit the SITE height to 32.35 in a local copy of the tech LEF.** Clean, matches what
   the PDK's own OpenLane config asserts (`PLACE_SITE_HEIGHT 32.35`), and recovers the
   36 % of core area the row-deletion hack wastes.
2. Keep 25.35 and delete alternate rows with `deleteRow` after `floorPlan`.

⚠️ **Option 1 is only safe if rows alternate orientation (N / FS) so adjacent rows share
rails.** If they do not, a 25.35 pitch puts one row's VDD across the next row's GROUND.
**Never tested on this PDK in either flow.** Verify with a two-row case and an LVS.

### 2.2 🔴 REVISED — extraction is not impossible, it is *authorable*

The first draft said Innovus would fall back to LEF-derived RC and inherit the 1000×
`CPERSQDIST` bug. **The UG says something different, and better.**

Verbatim, UG chapter 8, *Generating a Capacitance Table*:

> "For higher than 32nm technology nodes, either Quantus technology files or capacitance
> tables need to be specified. If neither of these is provided, Innovus generates a basic
> capacitance table using the default process parameters and heuristic equations for
> calculation. **However, this severely compromises accuracy.**"
>
> "For 32nm and below technology nodes, Quantus technology files must always be provided."

Three consequences, all in our favour:

1. **At 0.8 µm we are far above 32 nm, so a QRC techfile is *not* mandatory.** Captable
   extraction is the documented, supported path for this node. The missing `.tch` is not
   the blocker it looked like.
2. **With no captable, Innovus does not read the broken LEF capacitance — it synthesises
   its own table from defaults and heuristics.** So the 1000× bug may not propagate at
   all. It also means the numbers come from Cadence's generic assumptions about a process
   it knows nothing about. Either way: *do not trust them, and do not assume you know
   which failure mode you are in.* Check what the tool actually used before quoting a
   number.
3. **A captable can be generated**, from an **ICT file** plus the tech LEF. The UG lists
   what an ICT file needs:

| ICT input | Available for CP8D? |
|---|---|
| conductor min width and spacing | ✅ LEF + DRC deck: m1 W 1.7 / S 1.2, m2 W 2.0 / S 1.4 |
| conductor thicknesses | ⚠️ LEF says `THICKNESS 1` for **both** metals — suspicious, likely a placeholder |
| heights above substrate | ⚠️ LEF says `HEIGHT 1` for **both** — same concern |
| resistivities (sheet R) | ✅ `RPERSQ` 0.07 / 0.04, plus the doc's sheet-R table |
| interlayer dielectric constant, height, thickness | ❌ **not in the kit** |
| via top/bottom layers + contact resistance | ✅ `VIA M2_M1 ... RESISTANCE 3.375000e-01` |

So **one genuine gap** — the interlayer dielectric stack — and two values that are
present but look like placeholders. That is a tractable question to put to SCL, and it is
a far more useful ask than "please supply a QRC techfile."

**This also reframes the OpenLane result.** The null OpenRCX deck and the absent ICT data
are the same underlying gap: *SCL did not publish the dielectric stack for this process.*
Neither flow can do real extraction without it, and that is a PDK-completeness issue, not
a tool choice.

Until that is resolved, override RC explicitly and label every number:

```tcl
setLayerRC -layer metal1 -capacitance 2.46e-4 -resistance 4.12e-5
```

i.e. read the declared `0.027` as **fF/µm²**, not pF/µm². Sanity bound from SCL's own
datasheet: ~0.006 pF ≈ 24 µm of metal1.

### 2.3 Two metal layers constrain NanoRoute as much as TritonRoute

`tech_cp8d.lef` declares exactly six layers: diffusion, poly, contact, metal1 (horizontal,
pitch 3.7), via, metal2 (vertical, pitch 3.9).

- Power rails and horizontal straps share **metal1** with signal routing.
- **Never add vertical metal2 power stripes** — metal2 is the only vertical signal
  resource.
- `MANUFACTURINGGRID 0.005`, `DATABASE MICRONS 1000`.
- **LEF `VERSION 5.3`**, Abstract Generator 5.5.12, **2004**. Innovus 25.13 supports most
  of LEF 5.7, so 5.3 parses without complaint — it is simply missing two decades of
  constructs, which is exactly the problem in §3.1.

### 2.4 GDS streamout is available and well documented

Everything needed exists: `std_cells_cp8d.gds`, `pads_cp8d.gds`, `CORNER.gds` for the
merge, and `libs.tech/klayout/tech/scl_cp8d.map` for the numbering. The map is in KLayout
format, but carries the same layer/datatype pairs, so a Cadence map is a mechanical
translation. The numbers are also readable straight out of the DRC deck:

```
nwell 1/0 · diffusion 2/0 · nwell_rev 3/0 · poly 4/0 · boron_rev 5/0 · boron 6/0
contact 7/0 · metal1 8/0 (label 8/7) · via 9/0 · metal2 10/0 (label 10/7) · pad 11/0
```

UG chapter 3 documents `streamOut -merge {...}` with an explicit warning worth heeding:
when two merge files contain a cell of the same name, **the first file wins and the
second copy is silently dropped**, unless `-uniquifyCellNames` is used. With three PDK
GDS libraries merging into one stream, check for name collisions rather than assuming.

**This is the natural handoff point: Cadence produces the GDS, KLayout verifies it.**

---

## 3. 🔴 The part the UG changed most — Innovus *does* have DRC

### 3.1 `verify_drc` reads the tech LEF, not a foundry deck

This was the single biggest correction. From UG chapter 9:

> "`verify_drc` uses the drc rules in the tech lef file to check for violations caused by
> vias."

And the UG then lists the LEF statements `verify_drc` actually consumes:

```
ADJACENTCUTS · CORNERFILLSPACING · CUTCLASS SPACINGTABLE · ENCLOSURE · ENCLOSUREEDGE
ENDOFLINE · EOLENCLOSURE · EOLKEEPOUT · EOLSPACING · EXCEPTRECTANGLE · JOGTOJOGSPACING
MANUFACTURINGGRID · MAXVIASTACK · MINSTEP · MINWIDTH · OPPOSITEEOLSPACING · PINMASK
SPACING · VOLTAGESPACING · WIDTH
```

plus two **prerequisites**: `CLEARANCEMEASURE` and `USEMINSPACING`.

**Now compare against what `tech_cp8d.lef` actually contains.** Per layer it has only
`TYPE`, `DIRECTION`, `PITCH`, `OFFSET`, `WIDTH`, `SPACING`, `RESISTANCE`, `CAPACITANCE`,
`EDGECAPACITANCE`, `HEIGHT`, `THICKNESS`, `WIREEXTENSION`, plus a `SPACING SAMENET`
block, one `VIA`, one `VIARULE GENERATE`, and five `SITE`s.

| `verify_drc` input | in `tech_cp8d.lef`? |
|---|---|
| `WIDTH`, `SPACING` | ✅ yes — the only two |
| `MANUFACTURINGGRID` | ✅ yes (0.005) |
| `CLEARANCEMEASURE` — *prerequisite* | ❌ |
| `USEMINSPACING` — *prerequisite* | ❌ |
| `MINWIDTH`, `MINSTEP`, `ENCLOSURE`, `ENDOFLINE`, `EOLSPACING`, `SPACINGTABLE`, `ADJACENTCUTS`, `MAXVIASTACK`, … | ❌ none |

⇒ **`verify_drc` will run on CP8D and check minimum width, basic spacing and the via
rule. Nothing else.** Neither documented prerequisite is met.

**This is more dangerous than a blocked tool.** A blocked tool tells you it is blocked. A
near-empty rule set returns a clean report that looks like a signoff and is not. The same
trap as `GRT_REPAIR_ANTENNAS` in the OpenLane config: machinery enabled, nothing behind
it.

It also sharpens §3 of the original argument: Innovus's DRC is not *absent*, it is
**structurally thinner than KLayout's**. The SCL deck implements **71 rule categories**
including boron width, well spacing, poly extension, contact enclosure and pad spacing —
none of which are expressible in a LEF at all, because LEF describes routing layers, not
the front end.

**Practical rule: `verify_drc` on CP8D is a routing sanity check, not DRC.** Useful
after detailed routing to catch gross errors early; it is not evidence of anything and
must never be reported as DRC clean.

### 3.2 `verify_antenna` has nothing to work with — confirmed from both sides

UG chapter 9, prerequisites for antenna verification:

> "Ensure the antenna keywords are specified in the LEF file. For example:
> `ANTENNAAREARATIO` for LEF layers; `ANTENNAGATEAREA` and `ANTENNADIFFAREA` for macro
> pins."

And `tech_cp8d.lef`'s own header records how it was generated:

```
# Options:   [ ] Antenna
#            [ ] Geometry
#            [x] Technology
```

**The antenna option was switched off at generation time.** There are no antenna ratios
in the tech LEF and no gate/diffusion area fields on the cell pins.

⇒ `verify_antenna` runs and reports nothing, for the same reason OpenLane's
`GRT_REPAIR_ANTENNAS 1` and `USE_ARC_ANTENNA_CHECK 1` find nothing. **Two independent
tools, same silent pass, same root cause.** This is now confirmed from the Cadence side
as well as the open-source side, and it is the strongest evidence that the antenna gap
(B1 in the caveat register) is real and not a search artefact.

That same `[ ] Geometry` line is also why the abstract has no poly — the reason router
DRC and signoff DRC disagree about via-over-poly.

### 3.3 What Innovus verification *is* good for here

- **`verifyConnectivity`** — works on the DEF alone, needs nothing from the PDK. Catches
  opens, floating nets, dangling wires. Genuinely useful.
- **`verifyMetalDensity` / `verifyCutDensity`** — need density rules in the LEF; CP8D has
  none, so these are silent passes too.
- **Violation Browser** — works with whatever markers exist, and the UG notes
  `verify_drc` and `verifyMetalDensity` can be re-run incrementally inside a session.

---

## 4. Foundry signoff PV — still impossible, and still pointless

Unchanged by the UG, and worth restating because §3 might read as a softening.

**It cannot be done.** Pegasus, PVS and Assura each need a rule deck in their own
language. SCL ships a KLayout `.drc` (24,627 B, 71 categories) and a KLayout `.lvs`.
Translating that by hand produces *your* interpretation of the rules, carrying none of
the foundry's authority — which is the entire point of a signoff deck.

**It would not be accepted.** echiphub requires a DRC report produced by **SCL's own
KLayout deck**, named `Silicon no._Design Name_Date_Version_drc.txt`. Even with a perfect
Pegasus deck you would still run KLayout to produce the submittable artefact.

⇒ **For this PDK, PV is a KLayout activity by definition.** Not a limitation to engineer
around; it is the specified flow.

Corroboration from the kit: SCL's own pad-frame verification evidence in
`PadFrame_cp8d/Padframe_database/report/` is **ten PNG screenshots**
(`drc_1mmx1mm.png` … `lvs_5mmx5mm.png`) — images of a KLayout session, not
machine-readable reports. Even the foundry's own signoff evidence for this kit is
KLayout.

---

## 5. What this means for a "PD and PV" goal

| Goal | On CP8D | Where it actually lives |
|---|---|---|
| Cadence **PD** (Genus/Innovus/Tempus) | ✅ feasible, §2's fixes | Also already proven on gpdk045 — the 45 nm ALU closed at +5.716 ns worst setup across all 22 endpoints |
| **PV as a discipline** | ✅ via KLayout | 71 rule categories, real violations, real debugging |
| **Cadence PV tools** (Pegasus/PVS) | ❌ not on this PDK | Needs a PDK shipping a Cadence deck |
| **Tape out** on CP8D | ✅ OpenLane + KLayout | Cadence can contribute netlist and GDS; signoff cannot be Cadence |

**The highest-value use of Cadence here is as a cross-check.** Genus-vs-Yosys cell
counts; Innovus-vs-OpenROAD timing and congestion; and now a third, sharper one:
**`verify_drc` vs the KLayout deck on the same GDS.** The gap between them is a direct
measurement of how much of this process LEF cannot express — that is a genuinely
interesting result and nobody has published it.

---

## 6. Open questions

1. **Does the row orientation alternate?** §2.1 depends on it; never checked in either
   flow. One two-row case plus LVS settles it.
2. **What is the interlayer dielectric stack?** §2.2 — the one genuine ICT gap. Also
   explains why OpenRCX ships empty. Worth asking SCL directly; it is a more answerable
   request than a QRC techfile.
3. **Are `THICKNESS 1` and `HEIGHT 1` real?** Both metals carry identical values in a
   2004-generated LEF. If placeholders, they contaminate any LEF-derived extraction.
4. **Licensing.** The deck header reads *"Provided SOLELY under SCL NDA for
   evaluation/internal use. No redistribution, sublicensing, or public disclosure
   permitted."* Running an NDA foundry kit through commercially licensed tools is a
   question neither document obviously answers.
5. **What does Innovus actually use for RC with no captable?** §2.2 — the UG says it
   generates one from defaults. Whether the broken `CPERSQDIST` leaks in anyway is
   untested and would take one `setExtractRCMode` experiment to find out.

---

## 7. Summary

| Claim | Verdict |
|---|---|
| "Up to netlist generation is fine" | **Understated.** Genus, Innovus, routing and streamOut all work. |
| "The goal is tapeout" | **Reachable — the signoff half must be KLayout.** |
| "The main deal is PD and PV" | **PD: feasible. PV: Innovus has `verify_drc`, but on this PDK it checks almost nothing and must never be quoted as DRC clean. Foundry signoff is KLayout, by SCL's requirement.** |

One-line version: **Cadence can build it and can sanity-check it, but only KLayout can
sign it off — and SCL will only read KLayout's report.**

The sharpest new fact: **Innovus's DRC and its antenna check will both run on CP8D and
both come back clean, because the 2004-vintage tech LEF contains almost none of the
statements they read.** A clean report from a tool that was given nothing to check is the
most expensive kind of false confidence in this whole assessment.
