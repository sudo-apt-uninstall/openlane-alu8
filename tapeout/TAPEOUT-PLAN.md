# alu8 → SCL CP8D tapeout: plan, inputs, and what actually blocks it

**Status: NOT tapeout ready.** This directory holds the chip-level inputs and an
honest gap register. Nothing here has been executed. The 1 mm learning run in
`flow/` is complete and signed off except for 3 DRC violations; everything below
is the work between that and a submittable GDS.

Scope note: this is an individual learning project. It is **not** a funded shuttle
submission, and nothing in this file should be read as one.

---

## 1. Target

| | value | source |
|---|---|---|
| die | **4 mm × 4 mm** | SCL pad-frame database, `frame4mmx4mm.gds` |
| pads | **40** = 32 usable I/O + 8 power | SCL pin-budget table, die→pad mapping |
| core opening | **`304.90 304.90 3695.10 3695.10`** = 3390.2 µm square | **measured** from `frame4mmx4mm.gds` by KLayout batch |
| pad pitch | **350.00 µm** | measured (700.95 − 350.95) |
| design I/O | **29** (19 in + 10 out) | `rtl/alu8.sv` |
| headroom | 29 of 32 | |

The design is **pad-limited, not core-limited**: 210 standard cells occupy roughly
0.45 mm² against 11.5 mm² of core. The 4 mm die is chosen by pin count alone.

⚠️ `304.90 … 3695.10` is measured, not derived. An earlier value of
`305 305 3695 3695` appears in older notes — it was a guess that happened to land
within 0.1 µm. Use the measured one.

### Why `config_chip.json` grows the die instead of merging a small core

`CORE_AREA` is set to the frame's **measured core opening**. The routed core GDS
then sits on the frame's own coordinates, so merging it into `frame4mmx4mm.gds`
is an overlay at the origin with **no translation step** — and no opportunity for
a translation error that DRC would catch only at the pad ring.

`DESIGN_NAME` deliberately stays `alu8`: `yosys_script.tcl` hardcodes
`$::env(DESIGN_NAME).v` and every `3_src` script keys off the same name, so the
chip run reuses all 11 scripts **unedited**. Only `config.json` and
`pin_order.cfg` differ between the 1 mm run and the chip run.

---

## 2. Pin assignment — and the pad conversion arithmetic

`pin_order_chip.cfg` splits the 29 pins **8 / 8 / 8 / 5**:

| edge | pins | count |
|---|---|---|
| N | `a[7:0]` | 8 |
| S | `b[7:0]` | 8 |
| E | `result[7:0]` | 8 |
| W | `op[2:0]`, `zero`, `carry` | 5 |

**Every edge carries exactly 8 signal positions — measured, not assumed.** Signal
pads sit at 350.95 / 700.95 / 1050.95 / 1750.95 / 2100.95 / 2800.95 / 3150.95 /
3500.95 on all four edges; the two remaining positions per edge are power:

| edge | coord | power |
|---|---|---|
| S | y = 304.90 | PVSS @ 1400, PVDD @ 2450 |
| W | x = 304.90 | PVDD @ 1400, PVSS @ 2450 |
| E | x = 3695.10 | PVSS @ 1400, PVDD @ 2450 |
| N | y = 3695.10 | PVDD @ 1400, PVSS @ 2450 |

⇒ An earlier 8/8/**10**/3 split is impossible. The E edge cannot hold 10.
🔴 **Power pad position and type must not be altered** (SCL rule).

### 🔴 The frame ships ZERO output pads

Per edge the 8 signal positions alternate **4 × `SPAD00` + 4 × `ASPAD00`**.
Frame-wide: **16 `SPAD00` + 16 `ASPAD00`**.

- `SPAD00` — 4 terminals (`GROUND PAD PADn_OUT VDD`) — **input only**.
- `ASPAD00` — **3 terminals** (`GROUND PADIN VDD`) — a bond pad, a 322 Ω nwell
  resistor (`W=45u L=14.5u`) and four ESD diodes. **No path to the core at all.**
  Proven from `io_pad_cp8d.cdl`, not inferred.

⇒ As shipped, the 4 mm frame offers **16 inputs, 16 dead pads, 0 outputs.**
Pad conversion is **mandatory**, at every die size — the alternation is identical
in all five frames. CP8D does ship the pads needed: non-inverting outputs
`OTPD01/02/03/04` (2/4/8/16 mA), tristates `OTTR01/02/03`, bidirs `BPT1xx/2xx/3xx`.

**Conversion count depends on the pin assignment** (arithmetic, derived from the
measured frame):

| assignment | conversions | cost |
|---|---:|---|
| bus-aligned 8/8/8/5 as above | **18** | N:4, S:4 (`ASPAD00`→`SPAD00`); E:8 (all 8 → `OTPD0x`); W:2 (`ASPAD00`→`OTPD0x`) |
| conversion-minimal | **13** | put all 10 outputs on `ASPAD00` slots (10 → `OTPD0x`) + 3 `ASPAD00`→`SPAD00` for the 19th input |

13 is the global floor (19 inputs − 16 `SPAD00` = 3, plus 10 outputs). Reaching it
scatters `result[7:0]` across all four edges, which fights core routing on a
2-metal process. **18 is the honest number for a clean bus-aligned floorplan.**

🔴 Every conversion requires editing **`frame4mmx4mm.cdl`** to match the GDS. The
pad-frame guide's Step 3 and Step 6 permit pad replacement **only** on that
condition. A GDS/CDL mismatch here fails LVS at the chip level, not the core level.

⚠️ **No corner cells are instantiated in the 4 mm frame.** `CORNER.gds` and
`corner_cp8d.lef` ship and are listed in `GDS_FILES`, but the four corners of the
frame are empty. Do not assume the frame is complete because the cells exist.

### Output drive is undecided

`OTPD01/02/03/04` = 2/4/8/16 mA. No load spec exists for this project, so the
choice is unmade. ⚠️ SCL's own documents **contradict each other** on pad drive
(`BPT101` 2 vs 4 mA, `BPT201` 8 mA vs pull-up 2 mA, `OTTR03` 8 vs 4 mA).
**Trust `cp8d_pads_typ.lib`, not the PDFs.**

---

## 3. What is ON DISK and what is genuinely blocked

🔴 This section corrects earlier drafts of this plan, which listed held artefacts
as missing. "Not read" was being logged as "not held" — different states.

### Held (in the SCL CP8D PDK tree we already have)

- `frame4mmx4mm.gds` and `frame4mmx4mm.cdl` — the frame itself, measured above.
- `io_pad_cp8d.cdl` (43,539 B) — all pad netlists; this is what proved `ASPAD00` dead.
- The CP8D pad-frame PDF and both digital reference documents.
- `cp8d_drc.drc` — **v1.1, 16/09/2026, 24,627 B, sha `7634e4ab5a450fe28211e039aa798e0180111092`.**
  Re-check the portal against this sha before submitting.
- `report/drc_cp8d_report/` and `report/lvs_cp8d_report/` — SCL's own signoff on
  their own frame. **Directories, still unread.** Potentially relevant to the
  INVR00 boron violations: if SCL's own frame report carries the same rule, the
  question is answered without running anything.

### 🔴 Genuinely blocked on SCL / NIELIT — these three are the real wall

| # | blocker | why it blocks |
|---|---|---|
| **G-01** | **No antenna rule deck.** Grepping the entire CP8D tree (102 dirs / 264 files) **and** all five SCL PDFs for `antenna` returns **zero hits** — yet submission requires a *"DRC/**Antenna** clean GDSII"*. | We can be DRC-clean and still un-submittable, with **no way to self-check**. Ask whether a 2-metal 0.8 µm process is antenna-exempt. **Do not assume it is.** |
| **G-02** | **Tapeout Submission Form** — named 4× across the MPW page and the procedure document, never seen. | Carries the compliance checklist SCL inspects against *and* the Mask Technology Development Division contacts needed to obtain a silicon number. Gates both ends. |
| **G-03** | **Seal ring + layer-revision / silicon-number block.** The MPW page says the readme and GDS *"are given in the PDK"*; tree grep for `seal`/`ring`/`revision`/`silicon` returns **zero hits**. | ⚠️ `CORNER.gds` / `corner_cp8d.lef` are pad-ring **corner cells**, NOT a seal ring. Do not substitute one for the other. |

Lesser, non-blocking: designer-side submission date unpublished; bonding diagrams
and CoB footprints come via the portal (bonding is **fixed one-to-one with pin-out**,
so pad order on the frame *is* the package pinout — freeze pad order before
requesting them); C2S participating-institution status unverified.

---

## 4. 🔴 The hard technical blocker we own: 3 DRC violations that cannot be waived

Signoff DRC on the 1 mm run reports **3 violations**, all
`6.1.1 / 6.1.2 minimum boron width 3.4 µm`, each measuring **3.35 µm — 50 nm short**.
All three are on `INVR00`: `_281_` (468.0, 152.1), `_257_` (744.9, 152.1),
`_252_` (643.5, 354.9).

**They are one defect, not three.** Subtracting each instance origin gives the
violation at **Δx = 0.00, Δy = +17.35 / +20.70 in all three**, to the decimal —
on the cell's left boundary, in a fixed band of a 32.35 µm row.

**LVS passes with 0 errors**, so the fault is purely geometric: the layout *is*
the schematic, it just isn't manufacturable as drawn.

⚠️ **Waiving is unavailable in principle.** The undocumented `999:0` waiver layer
is **hard-capped at 2 polygons** and there are 3 violations. **At least one must
be genuinely fixed.**

Two candidate causes, one deciding experiment each:

1. **Abutment artefact** — every violating `INVR00` sits Δx = 15.6 from an `NND200`
   with no gap; every clean `INVR00` has a gap (19.5 / 23.4 / 35.1). The one
   `INVR00` at Δx = 15.6 from a `NOR200` passes, so it is the specific
   `NND200`↔`INVR00` seam, not the spacing alone.
   → **Test: the chip run in this directory.** Occupancy falls from ~33 % to
   ~0.4 %; if the violations vanish, this is confirmed and `PL_TARGET_DENSITY` is
   the lever. **This test is free — it is a side effect of a run we want anyway.**
2. **Library defect in `INVR00`** — corroborated by SCL's own
   `DRC_EXCLUDE_CELL_LIST_OPT "INVR01"` in `runs/RUN.bak/config.tcl`: SCL excluded
   an `INVR`-family inverter from DRC.
   → **Test: run the deck on `INVR00` standalone** from `core_cp8d.lef` /
   `std_cells_cp8d.gds`. >0 items ⇒ PDK defect record, and the fix is not ours.

⚠️ A plain re-run **cannot** change this. The flow is byte-identically
deterministic through signoff — the same 3 items at the same coordinates came back
against a freshly regenerated GDS. Closure requires changing an **input**.

---

## 5. Ordered work list

Core-side, in dependency order:

1. **Read `report/drc_cp8d_report/` and `report/lvs_cp8d_report/`.** Free, already
   held, and may answer §4 outright.
2. **Standalone `INVR00` DRC.** Decides library-defect vs abutment. One command.
3. **Run `run_chip.tcl`.** Gives the 4 mm core GDS *and* the density experiment.
4. **Gate-level simulation** — `alu8_rt_sim.v` + `alu8_rt.sdf`, never run. The only
   step that verifies the routed netlist **computes correctly**. Also closes the
   SCL procedure's Table 5 deviation #2.
5. **Confirm `signoff.sh`** (`../signoff/signoff.sh`) — one-time confirmation of
   the deck `-rd` names, after which signoff stops being a manual GUI ritual.

Chip-side, after 1–5:

6. Choose the pin assignment (18-conversion bus-aligned vs 13-conversion minimal).
7. Choose output drive from `cp8d_pads_typ.lib`.
8. Swap pads in `frame4mmx4mm.gds` **and** edit `frame4mmx4mm.cdl` to match.
9. Merge the core GDS into the frame (overlay at origin, by §1).
10. Chip-level DRC + LVS against the merged GDS and the edited frame CDL.
11. Seal ring, antenna check, submission form — **blocked, see §3**.
12. Silicon number, naming convention, MD5 — clerical, applied at submission.

Steps 1–10 are ours. Step 11 is not, and no amount of core-side work removes it.

---

## 6. What "tapeout ready" would mean here

The flow is **reproducible and deterministic** — that part is done and auditable.
It is **not** signoff-clean, and the chip level does not exist yet. Concretely,
three things must all become true:

- [ ] signoff DRC returns **0 items** on the merged chip GDS (today: 3 on the core, unwaivable)
- [ ] chip-level LVS matches against the **edited** frame CDL (today: core LVS clean, chip not built)
- [ ] antenna-clean per an SCL-supplied deck (today: **no deck exists to run**)

Until all three hold, this repository documents a **completed, signed-off-except-DRC
learning run plus a costed plan** — not a tapeout.
