# Feasibility: SCL CP8D (0.8 µm) through a Cadence flow

Assessed 2026-10-23. Evidence is the kit itself (`sudo-apt-uninstall/SCL_0.8-um-PDK`,
102 directories / 264 files), the OpenLane runs in this repository, and the 45 nm
Cadence run in `sudo-apt-uninstall/alu-8bit-private`.

**The question as posed was "up to netlist generation is fine I think, but the goal is
tapeout, and the main deal is PD and PV." That framing is wrong in both directions.**

- **Better than assumed:** it does not stop at the netlist. **Genus and Innovus can both
  run**, through placement, CTS, routing and GDS streamout. Physical design in Cadence
  on this PDK is feasible.
- **Worse than assumed:** **physical verification in Cadence is impossible, and will
  stay impossible.** Not "hard" — there is no rule deck to run, and SCL would not accept
  its output if there were.

---

## 1. What each tool needs, and whether the kit has it

| Tool | Needs | Ships? | Verdict |
|---|---|---|---|
| **Xcelium** | Verilog cell models | ✅ `libs.ref/digital_cp8d/verilog/cp8d.v` | **works** |
| **Genus** | Liberty, optionally LEF | ✅ 6 `.lib` (core+pads × min/typ/max), 3 cell LEF | **works** |
| **Innovus** | tech LEF + cell LEF + Liberty | ✅ `tech_cp8d.lef`, `core/pads/corner_cp8d.lef` | **works, 3 fixes** |
| **Innovus streamOut** | cell GDS + layer map | ✅ `std_cells_cp8d.gds`, `pads_cp8d.gds`, `CORNER.gds`, `scl_cp8d.map` | **works, map needs translation** |
| **Tempus** | Liberty + SPEF | ⚠️ Liberty yes; SPEF only from a null RC deck | **runs, numbers meaningless** |
| **Conformal** | Liberty + Verilog | ✅ both | **works** |
| **Modus** (DFT) | Liberty with scan cells | ✅ `DFCL11` etc. in `cp8d_core_typ.lib` | **works in principle** |
| **Quantus / QRC** | QRC techfile `.tch` | ❌ **not in the kit** | **impossible** |
| **Pegasus / PVS / Assura** | rule deck | ❌ **not in the kit** | **impossible** |
| **Virtuoso** | `.tf`, `display.drf`, OA libs | ❌ **not in the kit** | **impossible** |

A filename search of the whole tree for `qrc`, `tch`, `assura`, `pegasus`, `cds.lib`,
`techfile`, `drf`, `virtuoso` and `calibre` returns **zero hits**. What ships instead is
the open-source equivalent set: KLayout DRC/LVS decks, Magic tech, xschem, OpenRCX.

So the kit is not "missing Cadence support" by accident — **it was built for an
open-source flow and has no Cadence front door at all.** The parts Cadence can consume
(LEF, Liberty, GDS, CDL, Verilog) are the format-neutral ones.

---

## 2. Physical design in Cadence — feasible, with three fixes

### 2.1 The site-height trap hits Innovus too, and the fix is different

`tech_cp8d.lef` declares `SITE CORE ... SIZE 3.900 BY 25.350 ;` while every cell is
drawn **32.35 µm** tall (rails overhang 3.5 µm each side). SCL's own OpenLane floorplan
script works around this by **deleting every odd row** after
`initialize_floorplan`.

In Innovus, `floorPlan -site CORE` will produce the same overlapping rows, and there is
no `odb::dbRow_destroy` equivalent to paper over it. Two options:

1. **Edit the SITE height to 32.35 in a local copy of the tech LEF.** This is the clean
   fix, it is what the PDK's own OpenLane config asserts
   (`PLACE_SITE_HEIGHT 32.35`), and it recovers the 36 % of core area that the
   row-deletion hack wastes.
2. Keep 25.35 and delete alternate rows with `deleteRow` after `floorPlan`.

⚠️ **Option 1 is only safe if rows alternate orientation (N / FS) so adjacent rows share
rails.** If they do not, a 25.35 pitch puts one row's VDD across the next row's GROUND.
This has **never been tested** on this PDK in either flow. Verify with a two-row
test case and an LVS before trusting it.

### 2.2 Extraction and timing are the real degradation

There is no QRC techfile, so Innovus falls back to **LEF-based RC**, which reads
`RPERSQ` and `CPERSQDIST` straight out of `tech_cp8d.lef` — and `CPERSQDIST` is
**1000× too large** (metal1 0.027 against C1D's 0.000027; 27 fF/µm² is physically
impossible at a 175 Å gate oxide).

Innovus will therefore produce confident, badly wrong timing, exactly as OpenSTA did
when fed the same number — that run reported an arrival time of 352,200,736 ns and
negative cell delays.

**Override it explicitly.** Innovus accepts per-layer RC directly:

```tcl
setLayerPreference ...   ;# not sufficient on its own
setLayerRC -layer metal1 -capacitance 2.46e-4 -resistance 4.12e-5
setLayerRC -layer metal2 -capacitance <derived> -resistance <derived>
```

i.e. read the declared `0.027` as **fF/µm²**, not pF/µm². Sanity bound from SCL's own
datasheet: ~0.006 pF ≈ 24 µm of metal1.

**This is an estimate, not signoff extraction.** Tempus will run and report numbers; they
carry the same caveat as the OpenLane ones. Quantus cannot be used to do better.

### 2.3 Two metal layers constrain NanoRoute as much as TritonRoute

`tech_cp8d.lef` declares exactly six layers: diffusion, poly, contact, metal1 (horizontal,
pitch 3.7), via, metal2 (vertical, pitch 3.9).

Consequences that carry over unchanged:

- Power rails and horizontal straps share **metal1** with signal routing.
- **Never add vertical metal2 power stripes** — metal2 is the only vertical signal
  resource there is.
- `MANUFACTURINGGRID 0.005`, `DATABASE MICRONS 1000`.
- LEF **version 5.3**, generated by Abstract Generator 5.5.12 in **2004**. Innovus reads
  it, but expect none of the modern constructs: no `PROPERTYDEFINITIONS`, no antenna
  fields, no `MINENCLOSEDAREA`.

### 2.4 GDS streamout is available, and the layer map is derivable

Everything needed exists: `std_cells_cp8d.gds`, `pads_cp8d.gds`, `CORNER.gds` for the
merge, and `libs.tech/klayout/tech/scl_cp8d.map` for the layer numbering.

That map is in **KLayout** format, not Cadence `gds2.map` format, but it carries the same
layer/datatype pairs, so a Cadence map can be written from it mechanically. The layer
numbers are also visible directly in the DRC deck:

```
diffusion 2/0 · nwell 1/0 · nwell_rev 3/0 · poly 4/0 · boron_rev 5/0 · boron 6/0
contact 7/0 · metal1 8/0 (label 8/7) · via 9/0 · metal2 10/0 (label 10/7) · pad 11/0
```

So `streamOut` with a merge list is a solved problem. **This is the natural handoff
point**: Cadence produces the GDS, KLayout verifies it.

---

## 3. Physical verification in Cadence — impossible, and also pointless

Two independent reasons, and the second is the one that settles it.

**It cannot be done.** Pegasus, PVS and Assura all need a rule deck written in their own
language. SCL ships a KLayout `.drc` (24,627 B) and a KLayout `.lvs`, and nothing else.
Translating a 71-category deck into Pegasus syntax by hand is weeks of work, and the
result would be *your* interpretation of the rules, carrying none of the foundry's
authority — which is the entire point of a signoff deck.

**It would not be accepted.** The echiphub submission requires a DRC report produced by
**SCL's own KLayout deck**, named `Silicon no._Design Name_Date_Version_drc.txt`. Even
with a perfect Pegasus deck you would still have to run KLayout to produce the
submittable artefact.

⇒ **For this PDK, PV is a KLayout activity by definition.** That is not a limitation to
work around; it is the specified flow.

A related point that is easy to miss: SCL's own pad-frame verification evidence in
`PadFrame_cp8d/Padframe_database/report/` is **ten PNG screenshots**
(`drc_1mmx1mm.png` … `lvs_5mmx5mm.png`) — images of a KLayout session, not machine-readable
reports. Even the foundry's own signoff evidence for this kit is KLayout.

---

## 4. What this means for a "PD and PV" goal

Separate the skill from the vehicle, because they have different answers.

| Goal | On CP8D | Where it actually lives |
|---|---|---|
| Learn Cadence **PD** (Genus/Innovus/Tempus) | ✅ feasible, with §2's fixes | Also already proven on gpdk045 — the 45 nm ALU run closed timing at +5.716 ns worst setup across all 22 endpoints |
| Learn **PV** as a discipline | ✅ via KLayout | DRC/LVS on CP8D is real PV work: 71 rule categories, real violations, real debugging |
| Learn **Cadence PV tools** (Pegasus/PVS) | ❌ not on this PDK | Needs a PDK that ships a Cadence deck — gpdk045 or whatever Wipro's training uses |
| **Tape out** on CP8D | ✅ but through OpenLane + KLayout | Cadence can contribute the netlist and even the GDS; signoff cannot be Cadence |

**The highest-value use of Cadence here is as a cross-check, not a replacement.** Running
the same RTL through Genus and comparing cell counts against Yosys, and through Innovus
and comparing timing and congestion against OpenROAD, is genuinely informative — it
exercises real PD skills, produces report material, and tests the PDK from a second
direction. Several of the defects already found were caught precisely because two
independent sources disagreed.

What it should **not** be is the tapeout path. That path is already proven end-to-end:
RTL → routed → LVS matched → signoff DRC, with one rule class already driven to zero.

---

## 5. Open questions, not yet answered

1. **Does the row orientation alternate?** Everything in §2.1 depends on it, and it has
   never been checked in either flow. One two-row test case with an LVS settles it.
2. **Licensing.** Running an NDA-marked foundry PDK through commercially licensed tools
   raises a question neither the PDK's terms nor the tool licences obviously answer. The
   deck header reads *"Provided SOLELY under SCL NDA for evaluation/internal use. No
   redistribution, sublicensing, or public disclosure permitted."* Worth asking before
   building a flow on the assumption.
3. **Can Innovus's LEF-based extraction be trusted at all at 0.8 µm?** With corrected
   per-layer RC it is an estimate; whether it is a *useful* estimate on a 2-metal process
   with 3.7/3.9 µm pitches is unknown. Comparison against the OpenLane result would
   answer it, and would be a good experiment in its own right.

---

## 6. Summary

| Claim | Verdict |
|---|---|
| "Up to netlist generation is fine" | **Understated.** Genus, Innovus and GDS streamout all work. |
| "The goal is tapeout" | **Reachable — but the signoff half must be KLayout.** |
| "The main deal is PD and PV" | **PD: yes, feasible. PV: impossible in Cadence, and not required, because SCL only accepts its own KLayout report.** |

The one-line version: **Cadence can build it, but only KLayout can sign it off, and SCL
will only read KLayout's report.**
