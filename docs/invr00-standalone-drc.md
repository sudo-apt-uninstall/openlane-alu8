# Standalone `INVR00` DRC — the deciding experiment

**Run on W0, 2026-10-22 21:06 UTC. Result: 0 violations.**

This settles open item 1. The three boron-width violations in the alu8 signoff
are an **abutment artefact**, not a PDK library defect.

---

## What was run

```bash
sclenv
cp $PDK_ROOT/scl_cp8d/libs.ref/digital_cp8d/gds/std_cells_cp8d.gds .
klayout -e std_cells_cp8d.gds
# GUI: set INVR00 as top cell, then run the DRC deck
```

Report header, verbatim — this is what makes the result trustworthy:

```xml
<description>SCL DRC runset</description>
<original-file>std_cells_cp8d.gds</original-file>
<generator>drc: script='.../scl_cp8d/libs.tech/klayout/tech/drc/drc.lydrc'</generator>
<top-cell>INVR00</top-cell>
```

The correct cell, out of the real cell GDS, against the real deck.

## The result

```xml
<items>
</items>
```

**Empty.** All **71 rule categories** were evaluated — nwell, diffusion, poly,
MOS length/area, boron (including `6.1.1 and 6.1.2 : Minimum Boron width
violations = 3.4um`, the rule that fails in the design), contacts, metal1,
via, metal2, bonding pad, guardbar, and the seven `@GUIDELINE` checks — and
every one of them reported nothing.

## What this proves, and what it does not

**Proves:** `INVR00` in isolation is DRC-clean. Its own boron geometry satisfies
the 3.4 µm minimum. The cell is not defective.

**Therefore:** the 3.35 µm strips found at `_281_`, `_257_` and `_252_` are
**created by placement**, not inherited from the library. They appear where an
`NND200` hard-abuts an `INVR00` with zero gap and the two cells' boron shapes
merge into a single strip that is 50 nm under minimum. This matches the
evidence already recorded: all three violations sit at the identical offset in
the cell frame (Δx = 0.00, Δy = +17.35 / +20.70), and the one `INVR00` that
abuts a `NOR200` at the same Δx = 15.6 passes.

**Consequence: `PL_TARGET_DENSITY` is the lever**, and the 4 mm chip run at
`0.05` is no longer just an experiment — it is the expected fix. At ~1.2 %
utilisation the placer has no reason to abut anything.

**Does not prove** that lowering density is *sufficient*. The chip run has to
be signed off to confirm the violations are gone. It is possible for the placer
to abut two cells even at low density if nothing discourages it.

### A hypothesis that is now dead

SCL's own `DRC_EXCLUDE_CELL_LIST_OPT "INVR01"`, found in `runs/RUN.bak/config.tcl`,
was read as corroboration that the `INVR` family had a known DRC problem. With
`INVR00` measured clean, that reading is **withdrawn**. Whatever SCL excluded
`INVR01` for, it is not this.

### Why this matters beyond one rule

Had the result been non-zero, the fix would have been outside our control: a
defect report to SCL and a wait. Zero means the problem is ours, in our
placement, and closable by changing an input we own. That is the better of the
two outcomes.

---

## Two toolchain facts established by the same run

**1. The DRC decks live one level deeper than assumed.**

```
$KLAYOUT_PATH/tech/drc/drc.lydrc
$KLAYOUT_PATH/tech/lvs/lvs.lylvs
```

not `$KLAYOUT_PATH/drc/`. `signoff.sh` was corrected.

**2. 🔴 The DRC report path is CWD-relative, and there is no override.**

The deck writes **`./scl_drc.txt` into whatever the current directory is**.
An earlier invocation was made from inside the PDK tree and duly deposited its
report at

```
$PDK_ROOT/scl_cp8d/libs.tech/klayout/tech/libraries/scl_drc.txt
```

overwriting the PDK's own copy. Re-running from `~/temp_file/klayout` wrote to
`~/temp_file/klayout/scl_drc.txt` instead, which is how the behaviour was
identified.

**Implications:**

- Every DRC run overwrites the same filename in the CWD. Two designs checked
  from one directory silently clobber each other.
- `signoff.sh` cannot redirect the report with `-rd`. It now runs DRC from a
  scratch directory and moves the report into `5_klayout/lvs_drc/` afterwards.
- This is the most likely explanation for the earlier `<generator>` mismatch,
  where a report referenced `/home/eda/alu8bit/PDK/...` while `PDK_ROOT` pointed
  at `/home/eda/cadence/pdk/echip/...`.

**Rule: always read `<original-file>`, `<top-cell>` and `<generator>` out of a
KLayout report before believing it.** All three are present in the header and
all three can silently be the wrong thing.

### A harmless error to expect

```
ERROR: Stream has unknown format: .../scl_drc.txt
```

KLayout restoring a previous session that had the report file open as a layout.
It is not a DRC failure; the run after it completes normally.

---

## Next

1. Run the 4 mm chip flow (`tapeout/run_chip.tcl`) at `PL_TARGET_DENSITY 0.05`.
2. Sign it off and count `<item>` elements. **0 closes the DRC blocker.**
3. If violations persist, the fix moves to discouraging the specific
   `NND200`↔`INVR00` abutment rather than lowering density globally.
