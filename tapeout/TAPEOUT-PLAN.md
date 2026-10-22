# alu8 → silicon: what is ready, what blocks, what to fetch

**Written 2026-10-22.** Status of the request "prepare a tapeout-ready run with
pins and the ring".

**Status: NOT tapeout ready.** Nothing in this directory has been executed.

Scope note: this is an individual learning project. It is **not** a funded
shuttle submission, and nothing here should be read as one.

---

## 1. The short version

A **core-hardening run for the 4 mm frame** can be prepared today and is here:
`config_chip.json`, `pin_order_chip.cfg`, `run_chip.tcl`.

A **tapeout-ready chip** cannot be assembled today, for three reasons that are
verified rather than suspected. The most important one is the thing asked for
by name.

---

## 2. 🔴 The ring does not exist in the PDK

The SCL MPW page states that the seal ring and its readme *"are given in the
PDK"*. They are not.

A content-level search of the complete CP8D tree — **102 directories, 264
files** — and of all five SCL PDFs returns **zero hits** for `seal`, `ring`,
`revision` or `silicon`.

⚠️ **The near-miss that must not be made:** `CORNER.gds` and `corner_cp8d.lef`
*do* ship, and they are listed in the flow's own `GDS_FILES`. They are
**pad-ring corner cells** — the four L-shaped pieces that join adjacent pad
rows. They are **not a seal ring**. A seal ring is the continuous metal and
diffusion guard around the die edge that stops dicing damage and moisture
ingress, and it normally carries the layer-revision and silicon-number block
that SCL uses to identify the die.

⚠️ Measured aside: the 4 mm frame instantiates **no corner cells at all** —
41 instances = 40 pads + `OS_SCL_logo$1` at (225, 60). Its corners are empty.
Do not assume the frame is complete because the cells exist in the PDK.

**Consequence:** the die boundary structure cannot be built from what we hold.
It has to come from SCL. This is the single hardest blocker and it is not
something a script can route around.

---

## 3. 🔴 There is no antenna rule deck

SCL requires a *"DRC/**Antenna** clean GDSII"*. Searching the whole tree and all
five PDFs for `antenna` returns **zero hits**.

So the design can be fully DRC-clean and still fail submission, **with no way to
self-check**. Worth asking SCL or NIELIT directly whether a 2-metal 0.8 µm
process is antenna-exempt — it may well be, since antenna effects scale with
metal-to-gate area ratio and two thin metal layers give little opportunity. But
**do not assume it**; get it in writing.

---

## 4. 🔴 The Tapeout Submission Form is missing

Named four times across the MPW page and the Procedure document. It carries the
compliance checklist SCL inspects against, and the Mask Technology Development
Division contacts needed to obtain a silicon number. It gates both ends of the
process — you cannot self-check compliance without it, and you cannot submit.

---

## 5. 🟠 The die has to grow — this is the real design change

**Pin budget is set by die size**, identically on both SCL PDKs:

| Die | Pads | Usable I/O | Power | Core |
|---|---:|---:|---:|---|
| 1 mm | 6 | 4 | 2 | ~390 µm sq |
| 2 mm | 16 | 12 | 4 | ~1390 µm sq |
| 3 mm | 28 | 24 | 4 | ~2390 µm sq |
| **4 mm** | **40** | **32** | **8** | **~3390 µm sq** |
| 5 mm | 52 | 44 | 8 | ~4390 µm sq |

Pad pitch is 350 µm — **measured and confirmed** (700.95 − 350.95) — and
**44 I/O is the hard ceiling** on any die.

alu8 has **29 signal I/O**: `a[7:0]` + `b[7:0]` + `op[2:0]` = 19 in,
`result[7:0]` + `zero` + `carry` = 10 out.

- 3 mm offers 24 → **too small**
- **4 mm offers 32 → fits, with 3 spare**

The learning run used a 1000 × 1000 µm die, which corresponds to the **1 mm
frame and 4 usable I/O**. It was never a chip-sized floorplan; it was a
convenient box for flow exposure. `config_chip.json` moves it to 4 mm.

### 🔴 The core opening is measured, not derived

| | value |
|---|---|
| die bbox | (0,0) – (4000,4000) |
| pad origin rows/cols | **304.90** and **3695.10** on both axes |
| **core opening** | **`304.90 304.90 3695.10 3695.10`** = **3390.2 µm square** |

Measured from `frame4mmx4mm.gds` by KLayout batch. This **supersedes** the
earlier `305 305 3695 3695` in this plan's first draft, which was explicitly
flagged as derived-not-verified and happened to land within 0.1 µm.

Setting `CORE_AREA` to the frame's own opening means the routed core GDS sits on
the frame's coordinate system, so the later merge is an **overlay at the origin
with no translation step** — removing a class of alignment error that would
otherwise surface only at chip-level DRC.

### The design becomes wildly pad-limited

Cell area is roughly **0.137 mm²** against an **11.5 mm²** core opening: about
**1.2 % utilisation**. Nothing is wrong with that — it is the normal condition
for a small design on a frame sized by pin count — but it is worth stating
plainly in any report, because the resulting layout looks almost empty and a
reviewer will ask.

> Cross-check, so the figure is not taken on trust: the 1 mm run reports
> **16 rows × 800 µm × 32.35 µm = 0.414 mm²** of row area at **~33 % occupancy**.
> 33 % of 0.414 mm² = **0.137 mm²**. The two independent numbers agree.
> ⚠️ An intermediate draft of this plan said 0.45 mm² / ~0.4 %. Both were wrong
> and mutually inconsistent; 0.45 mm² came from the *older, larger* ALU described
> below.

`PL_TARGET_DENSITY` is dropped to **0.05** so the placer spreads toward the pad
ring rather than clustering in the middle and routing everything outward. It is
also the cheapest available test of the DRC hypothesis in §7.

### A note on the older 40-I/O figure

An earlier plan recorded alu8 as 21 inputs + 19 outputs = **40 I/O**, needing
the 5 mm die. That referred to a **different, larger ALU** — clocked, 16-bit
result, with multiply. **The current alu8 is the 8-bit combinational version at
29 I/O.** The 4 mm die is the correct target for what exists now. Any note that
still says 5 mm, 40 I/O or 0.45 mm² is describing the other design.

---

## 6. 🟠 Pad order is frozen by bonding, not by preference

Bonding on this process is **fixed one-to-one with the pin-out**: pad order on
the frame determines the package pinout, and there is no bond-wire freedom to
fix a bad order afterwards. Die → package is a 40-pin DIP CoB at 4 mm.

So `pin_order_chip.cfg` is a **proposal, not a freeze**. It distributes
8 / 8 / 8 / 5 across N / S / E / W, deliberately different from the learning
run's 8 / 8 / 10 / 3.

🔴 **That difference is now a measurement, not a precaution.** Every edge carries
10 pads = **8 signal + 2 power**:

| edge | coord | power |
|---|---|---|
| S | y = 304.90 | PVSS @ 1400, PVDD @ 2450 |
| W | x = 304.90 | PVDD @ 1400, PVSS @ 2450 |
| E | x = 3695.10 | PVSS @ 1400, PVDD @ 2450 |
| N | y = 3695.10 | PVDD @ 1400, PVSS @ 2450 |

Signal positions, identical on all four edges: 350.95 / 700.95 / 1050.95 /
1750.95 / 2100.95 / 2800.95 / 3150.95 / 3500.95.

⇒ 8 signal positions per edge is a **hard ceiling**; the E edge cannot hold 10,
so the old split was impossible rather than merely risky.
🔴 **Power pad position and type must not be altered** (SCL rule).

### ⚠️ The pad trap — worse than "analog pads only"

Every shipped pad frame is populated with **analog input pads only** — CP8D
alternates `ASPAD00` / `SPAD00`, **4 of each per edge**. No digital output or
bidirectional pad appears in any shipped frame.

Proven from `io_pad_cp8d.cdl` (43,539 B), not inferred:

- `SPAD00` — 4 terminals (`GROUND PAD PADn_OUT VDD`) — **input only**.
- `ASPAD00` — **3 terminals** (`GROUND PADIN VDD`): a bond pad, a 322 Ω nwell
  resistor (`W=45u L=14.5u`) and four ESD diodes. **No path to the core at all.**
  It is not an "analog input" you could repurpose — it is a **dead pad**.

⇒ As shipped, the 4 mm frame offers **16 inputs, 16 dead pads, 0 outputs.**

**Conversion cost depends on the pin assignment:**

| assignment | conversions | why |
|---|---:|---|
| bus-aligned 8/8/8/5 | **18** | N:4 + S:4 `ASPAD00`→`SPAD00`; E needs **8** outputs but has only 4 `ASPAD00`, so 4 `SPAD00` must become `OTPD0x` too; W:2 |
| conversion-minimal | **13** | all 10 outputs placed on `ASPAD00` slots + 3 `ASPAD00`→`SPAD00` for the 19th input |

13 is the global floor (19 inputs − 16 `SPAD00` = 3, plus 10 outputs). Reaching
it scatters `result[7:0]` across all four edges, which fights routing on a
2-metal process. **18 is the honest number for a clean bus-aligned floorplan.**

The procedure document's "mandatory to use these provided pads" refers to the
**frame**; the pad-frame guide's Step 3 and Step 6 explicitly permit pad
replacement **provided `frame4mmx4mm.cdl` is edited to match**. A GDS/CDL
mismatch here fails LVS at the chip level, not the core level.

CP8D's digital pad set (20 cells) is the good news, and is materially easier
than C1D's: non-inverting outputs `OTPD01/02/03/04` at 2 / 4 / 8 / 16 mA,
tristate `OTTR01/02/03`, bidirectional `BPT1xx/2xx/3xx`. C1D by contrast has
*inverting* output pads requiring an explicit driver instantiated in RTL.

⚠️ Drive-strength tables **contradict each other across the three SCL PDFs** for
`BPT101` (2 vs 4 mA), `BPT201` (8 mA vs pull-up 2 mA) and `OTTR03` (8 vs 4 mA).
**Trust `cp8d_pads_typ.lib`, not the prose.** Output drive for this design is
still unchosen — no load spec exists.

---

## 7. 🟠 Signoff DRC is not clean yet — and cannot be waived

Three `6.1.1/6.1.2 Minimum Boron width` violations, all on **INVR00**, each
**50 nm** short of the 3.4 µm minimum (3.35 measured). Instances `_281_`
(468.0, 152.1), `_257_` (744.9, 152.1), `_252_` (643.5, 354.9).

They are deterministic — a byte-identical re-run reproduced them at the same
coordinates — and all three sit at the **same offset inside the cell frame**
(Δx = 0.00, Δy = +17.35 / +20.70), so it is one structural defect at three
sites, not three accidents. **LVS passes with 0 errors**, so the fault is purely
geometric: the layout *is* the schematic, it just is not manufacturable as drawn.

**They cannot be waived.** The undocumented `999:0` waiver layer is hard-capped
at 2 polygons; the deck raises and aborts beyond that, and there are 3. At least
one must be genuinely fixed.

Two candidate causes, one experiment each:

1. **Abutment artefact.** Every violating `INVR00` sits Δx = 15.6 from an
   `NND200` with no gap; every clean `INVR00` has a gap (19.5 / 23.4 / 35.1).
   The one `INVR00` at Δx = 15.6 from a `NOR200` passes, so it is that specific
   seam, not the spacing alone.
   → **Test: the chip run here.** At 1.2 % utilisation and
   `PL_TARGET_DENSITY 0.05` the placer has no reason to abut anything. **Free —
   a side effect of a run we want regardless.**
2. **PDK library defect.** → **Test: run the deck on `INVR00` standalone** from
   `core_cp8d.lef` / `std_cells_cp8d.gds`. Non-zero means the fix is not ours.
   Corroborated by SCL's own config carrying
   `DRC_EXCLUDE_CELL_LIST_OPT = "INVR01"` — they excluded an INVR-family
   inverter from DRC themselves.

⚠️ A plain re-run cannot change this. The flow is byte-identically deterministic
through signoff. Closure requires changing an **input**.

---

## 8. 🟡 Gate-level simulation has never been run

The inputs exist and are regenerated by every run: `alu8_rt_sim.v` (no supply
pins, so it drops straight into the existing testbench) and `alu8_rt.sdf`.

This is the only step that verifies the **routed netlist actually computes
correctly**. Taping out a design whose post-route netlist was never simulated is
not defensible. The existing testbench is 9 directed vectors; a full
`a × b × op` sweep is only 8 × 256 × 256 = **524,288** evaluations, which is
trivially runnable and would prove the design rather than sample it.

---

## 9. What is held, and what still has to be fetched

🔴 This section was rewritten after an audit: an earlier draft listed artefacts
as missing that were **already on disk, merely unread**. "Not read" is not "not
held", and conflating them wastes requests to SCL.

### Held and already used

| what | status |
|---|---|
| `frame4mmx4mm.gds` | **measured** — core opening, pad pitch, per-edge power coordinates, instance count |
| `frame4mmx4mm.cdl` | held; the file that must be edited for every pad swap |
| `io_pad_cp8d.cdl` (43,539 B) | **read** — this is what proved `ASPAD00` dead |
| `Standard_Pad_Frame_*.pdf`, Steps 3 and 6 | held — the sanctioned pad-replacement procedure |
| `cp8d_drc.drc` | held — **v1.1, 16/09/2026, 24,627 B, sha `7634e4ab5a450fe28211e039aa798e0180111092`**. Re-check the portal against this sha before submitting |

### Held but still unread — do these first, they are free

| what | why it matters |
|---|---|
| `report/drc_cp8d_report/` and `report/lvs_cp8d_report/` (directories) | SCL's own signoff on their own frame. If their report carries the same boron rule on an INVR-family cell, §7 is answered without running anything |
| `pads_cp8d.lef` — full `MACRO` list with `PIN` names, `SIZE`, `ORIGIN` | pad cells cannot be instantiated without exact port names and dimensions |
| `cp8d_pads_typ.lib` | the authoritative drive-strength table; the PDFs contradict each other |

### Not held — must come from SCL

| what | note |
|---|---|
| seal ring GDS + readme | **§2** — the hardest blocker |
| antenna deck, or written exemption | **§3** |
| Tapeout Submission Form | **§4** |
| bonding diagram / CoB footprint for the 40-pin DIP | fixes pad order ↔ package pin mapping before the order freezes |

Command sketch, since names must be listed rather than assumed:

```bash
sclenv                       # launcher, not sourceable: it execs bash --rcfile,
                             # so $PDK_ROOT expands to // in an existing shell
ls $PDK_ROOT/scl_cp8d/libs.ref/digital_cp8d/lef/
grep -i '^MACRO' $PDK_ROOT/scl_cp8d/libs.ref/digital_cp8d/lef/pads_cp8d.lef
find $PDK_ROOT -iname '*frame*' -o -iname '*pad*frame*'
find $PDK_ROOT -iname '*seal*' -o -iname '*antenna*'     # expected: empty
```

---

## 10. Staging — the order that does not waste work

1. **Read the two SCL report directories** (§9). Free, already held, may answer
   §7 outright.
2. **Close the DRC.** Standalone `INVR00` test, then either a placement change
   or a defect report. Nothing downstream is worth doing while signoff fails.
3. **Run gate-level simulation.** Cheap, and it is the functional gate.
4. **Re-run the core on the 4 mm floorplan** with the files here, and
   re-signoff. Expect the boron result to follow whatever step 2 concluded.
   `../signoff/signoff.sh` makes the re-signoff a command rather than a ritual,
   once its deck `-rd` names are confirmed one time.
5. **Fetch the frame data** in §9 and write the pad ring against real macro
   names. This is where pad order freezes, so the bonding diagram must be in
   hand first. Budget **18 pad conversions** for the bus-aligned order, and edit
   `frame4mmx4mm.cdl` for every one of them.
6. **Ask SCL for the three missing artefacts** — seal ring, antenna deck,
   submission form. Steps 1 to 5 are all useful regardless of the answer, so
   send the request now and work in parallel rather than waiting.

**Honest framing for a mentor conversation:** steps 1–5 are real engineering
work that is entirely in your control and produces a genuinely chip-shaped
result. Step 6 is a dependency on SCL that no amount of local effort removes.
Saying that plainly is stronger than presenting a "tapeout-ready" design with an
invisible hole where the seal ring should be.

---

## 11. What "tapeout ready" would mean here

Three conditions, all currently false:

- [ ] signoff DRC returns **0 items** on the merged chip GDS (today: 3 on the core, unwaivable)
- [ ] chip-level LVS matches against the **edited** frame CDL (today: core LVS clean, chip not built)
- [ ] antenna-clean per an SCL-supplied deck (today: **no deck exists to run**)

Until all three hold, this repository documents a **completed,
signed-off-except-DRC learning run plus a costed plan** — not a tapeout.
