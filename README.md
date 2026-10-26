<div align="center">

# `openlane-alu8`

**An 8-bit ALU taken from SystemVerilog RTL to routed, LVS-signed-off layout
on SCL's 0.8 µm CP8D open PDK — with the open-source OpenLane flow.**

`RTL → synthesis → floorplan → PDN → placement → filler insertion → routing →
parasitic extraction → STA → KLayout DRC/LVS`

**LVS match · router DRC clean · one-command, byte-reproducible flow**

</div>

---

## At a glance

| | |
|---|---|
| **Design** | 8-bit ALU, 8 operations, purely combinational, 29 I/O |
| **Process** | SCL Mohali **CP8D**, 0.8 µm, 2 metal layers, 5 V |
| **Tools** | OpenLane v1.0.2 (`ff5509f6`) · Yosys · OpenROAD · OpenSTA · KLayout |
| **Synthesis** | **210 standard cells**, ≈0.137 mm² of cell area |
| **Routing** | **`drc.rpt` 0 bytes** — router DRC clean on two metal layers |
| **LVS** | ✅ **0 errors — layout matches schematic** |
| **Critical path** | **11.61 ns** (`a[1]` → `zero`, 10 logic levels) ⇒ **≈86 MHz** |
| **Setup / hold** | **+88.39 MET** / **+0.78 MET** |
| **Reproducibility** | one `source flow/run_all.tcl`; a full re-run reproduces every artefact **byte-identically**, through signoff |

Companion project:
[`openlane-8bit-counter`](https://github.com/sudo-apt-uninstall/openlane-8bit-counter)
— the 8-bit counter that proved this flow end to end.

> Engineering status, measurement conditions, open work and the full experiment
> record live in **[docs/engineering-notes.md](docs/engineering-notes.md)**.
> Read that before quoting any number from this page.

---

## The routed layout

![Routed alu8 on SCL CP8D](docs/images/GDS-image.png)

210 logic cells and 356 fillers across 16 rows at ≈33 % occupancy, routed on the two
metal layers CP8D provides. The sparse look is deliberate — the die was fixed at
1000 × 1000 µm for pad-ring headroom rather than shrunk to the logic.

---

## The design

Purely combinational. No clock, no flip-flops. **29 I/O.**

```
in : a[7:0] + b[7:0] + op[2:0]        = 19
out: result[7:0] + zero + carry       = 10
                                        -- 29
```

| `op` | operation | notes |
|---|---|---|
| `000` | **ADD** | `temp = {1'b0,a} + {1'b0,b}`, `carry = temp[8]` |
| `001` | **SUB** | `carry` means **no borrow**: `carry = (a >= b)` |
| `010` | **AND** | |
| `011` | **OR** | |
| `100` | **XOR** | |
| `101` | **`a << b[2:0]`** | bits above 7 are dropped; `carry` unaffected |
| `110` | **`a >> b[2:0]`** | bits below 0 are dropped; `carry` unaffected |
| `111` | — | `default`: `result = 0`, `carry = 0` |

`zero` is computed from `result` *after* the `case`, so it is correct for every opcode
including `default`.

Two deliberate RTL choices, both of which reviewers often try to "fix":

- **Defaults are assigned at the top of `always_comb`, before the `case`** — so no
  latches are inferred. This is the single most common ALU bug, and it is designed out.
- **`temp` is 9 bits** and ADD zero-extends both operands, so carry-out is *captured*
  rather than lost to 8-bit truncation.

---

## Results

### Flow

| stage | result |
|---|---|
| **synthesis** (Yosys) | **210 CP8D standard cells**, ≈0.137 mm² cell area |
| **floorplan** | 1000 × 1000 µm die, 800 × 800 µm core, **16 rows**, 50.7 µm pitch, ≈33 % occupancy |
| **PDN** | metal1 followpins, 7 µm per row, metal1/metal2 ring |
| **placement** | `detailed_placement` + `check_placement` clean |
| **filler insertion** | **566 components = 210 logic + 356 FILLER** |
| **routing** | **`drc.rpt` 0 bytes — router DRC clean on 2 metal layers** |
| **RC extraction** | SPEF written and read back by the timer |
| **STA — setup** | **11.61 ns ⇒ ≈86.1 MHz**, path `a[1]` → `zero`, 10 logic levels, **+88.39 MET** |
| **STA — hold** | **+0.78 MET** — no min-delay problem |
| **signoff LVS** | ✅ **0 errors — layout matches schematic** |

Timing is quoted at the **typical corner, 5 V, 25 °C**, from cell delay; see
[docs/engineering-notes.md](docs/engineering-notes.md) for the measurement conditions
behind every figure on this page.

### Cell histogram

```
28 NND200   28 MX2100   23 ORND00   21 NOR200   20 INVR00   18 NND300
15 ADNR00    8 OR2100    8 AOI400    8 AND200    6 NOR300    5 XNR200
 4 XOR200    3 OAI400    3 AND500    3 AND300    2 OR3100    2 NND500
 2 AND400    1 NOR500    1 NND600    1 NND400
```

- **28 × `MX2100`** — the 2:1 mux tree implementing `case (op)`. Exactly as expected.
- **No flip-flops**, correctly — the design is combinational.
- **No `ADR100`** (the library's full adder): Yosys built the carry chain from ordinary
  gates, because ABC is invoked with no delay target and no SDC and therefore maps for
  **area**, where the larger full-adder cell loses. Not a library defect.

---

## Running it

The whole flow runs from a single driver, [`flow/run_all.tcl`](flow/run_all.tcl):

```bash
./flow.tcl -design project_scl_cp8d/alu8 -tag RUN -interactive -overwrite
% source $::env(DESIGN_DIR)/run_all.tcl
```

It executes synthesis → floorplan → PDN → placement → fill → routing → RCX → STA and
asserts after every stage that a non-empty artefact was produced. `run_openroad_script`
takes a **path** argument and prints nothing on success, so checking **file sizes** —
not merely existence — is the only reliable way to know a stage worked.

### Signoff

[`signoff/signoff.sh`](signoff/signoff.sh) is the headless driver: it builds the CDL and
the GDS, then runs KLayout DRC and LVS in batch and prints a verdict on stdout.
`signoff/cdl_gds_script.source` is the original GUI-based path, kept for provenance.

Operational detail — deck locations, report paths, run-tag handling — is in
[docs/signoff.md](docs/signoff.md).

---

## Making a combinational design fit a clocked reference flow

The SCL reference flow is built around a **clocked** counter. Seven input-side changes
adapt it; full detail in [docs/flow-notes.md](docs/flow-notes.md).

1. `alu8.sv` copied to `1_RTL/alu8.v` — the Yosys script hardcodes `DESIGN_NAME.v`.
   *The content stays SystemVerilog; only the extension changes.*
2. `-sv` added to `read_verilog` in `yosys_script.tcl`.
3. `config.json` — `CLOCK_PORT ""`, `CLOCK_NET ""`, `RUN_CTS false`, 1000 µm die.
4. `pin_order.cfg` — 29 pins distributed across the four edges.
5. `run_sta.tcl` — a **virtual clock** replacing `create_clock … [get_ports clk]`.
6. **`fill_cp8d.tcl`** — a hand-written CTS substitute that preserves filler insertion.
   The reference flow only inserts fillers *inside* CTS, so skipping CTS silently
   loses them.
7. `signoff/cdl_gds_script.source` — the signoff driver retargeted from the counter
   smoke test to `alu8`.

**Provenance:** of the 10 reference Tcl scripts, **8 are byte-identical to SCL's
upstream** — only `run_sta.tcl` and `yosys_script.tcl` differ, exactly the two edits
above. Every result here is stock-script output.

### Why there are no tap cells

A reasonable instinct on a CMOS flow is *"insert tap cells to guarantee well/substrate
contact."* **On CP8D there is nothing to insert:** the library ships no tap/welltap/subtap
macro at all — 65 LEF macros against 59 Liberty cells, and the six LEF-only ones are
exactly `FILLER1`…`FILLER6`. At 0.8 µm the well and substrate contacts are drawn *inside*
each standard cell and inside the fillers; the separate-tap-cell-on-a-pitch scheme is a
deep-submicron convention.

**On this process, filler insertion *is* the tap strategy** — which is precisely why the
`fill_cp8d.tcl` rescue above matters, and why every re-run verifies the filler count
explicitly.

---

## Chip-level inputs

[`tapeout/`](tapeout/) holds the chip-level configuration for a **4 mm × 4 mm**
pad-framed version. The plan, with the arithmetic behind every number, is in
[tapeout/TAPEOUT-PLAN.md](tapeout/TAPEOUT-PLAN.md); the executed chip run is written up
in [docs/chip-run-4mm.md](docs/chip-run-4mm.md).

| | value |
|---|---|
| die | 4 mm × 4 mm — 40 pads = 32 usable I/O + 8 power |
| design I/O | **29** of 32 — pin count fixes the die, not area |
| core opening | **`304.90 304.90 3695.10 3695.10`** — **measured** from `frame4mmx4mm.gds` |
| utilisation | ≈0.137 mm² of cells in an 11.5 mm² core = **≈1.2 %** — pad-limited |
| pin split | **8 / 8 / 8 / 5** — every edge has exactly 8 signal positions, the other two are power |

---

## Repository layout

```
rtl/        alu8.sv, tb_alu8.sv
flow/       run_all.tcl — single-command driver for the whole flow
            config.json, pin_order.cfg, 3_src/*.tcl as actually executed
results/    flattened artefacts: synthesis netlist, floorplan/placement/cts/
            routing DEFs, routed netlists (_pwr/_sim), SPEF, SDF, STA reports
signoff/    signoff.sh (headless DRC/LVS), cdl_gds_script.source +
            script/ (DEF→GDS, Verilog→CDL), and lvs_drc*/ holding the GDS, CDL,
            extracted netlist, LVS database and the KLayout DRC reports
tapeout/    chip-level inputs for the 4 mm pad frame — config_chip.json,
            pin_order_chip.cfg, run_chip.tcl, TAPEOUT-PLAN.md
runs/       raw run trees: RUN, RUN_COMPLETE_20261021, RUN.bak, CHIP
netlist/    alu8_netlist.v — generic Yosys output, kept for provenance only
docs/       engineering-notes.md — status, conditions and open work
            flow-notes.md, signoff.md, determinism.md, flow-script-audit.md,
            chip-run-4mm.md, padding-run-d020.md, invr00-standalone-drc.md,
            failed-runs.md, scl-pdk-caveats.md, cadence-flow-feasibility.md
MANIFEST.md byte sizes of every tracked artefact, and what was excluded
```

Both completed 1 mm run trees are preserved, and their `results/` are **byte-identical**
across two separate executions — the determinism claim in a form anyone can check:

```bash
diff -rq runs/RUN/results runs/RUN_COMPLETE_20261021/results
```

See [docs/determinism.md](docs/determinism.md).

---

## Documentation

| document | what it covers |
|---|---|
| **[engineering-notes.md](docs/engineering-notes.md)** | **current status, measurement conditions, open work, known gaps** |
| [flow-notes.md](docs/flow-notes.md) | running a combinational design on a clocked reference flow |
| [signoff.md](docs/signoff.md) | DRC/LVS methodology and the signoff analysis |
| [determinism.md](docs/determinism.md) | the byte-identical re-run, and what it implies |
| [flow-script-audit.md](docs/flow-script-audit.md) | what the reference scripts actually execute |
| [chip-run-4mm.md](docs/chip-run-4mm.md) | the 4 mm pad-framed chip run |
| [padding-run-d020.md](docs/padding-run-d020.md) | placement padding: the experiment and its result |
| [invr00-standalone-drc.md](docs/invr00-standalone-drc.md) | standalone cell DRC — the deciding experiment |
| [failed-runs.md](docs/failed-runs.md) | what each preserved run tree is, and is not |
| [scl-pdk-caveats.md](docs/scl-pdk-caveats.md) | PDK behaviour worth knowing before you start |
| [cadence-flow-feasibility.md](docs/cadence-flow-feasibility.md) | the same design through a commercial flow |

---

## Credits and licensing

PDK: **SCL Mohali** 0.8 µm CP8D open PDK, distributed via echiphub.in / NIELIT.
**The PDK itself is not redistributed in this repository.**

Tooling: OpenLane v1.0.2 (`ff5509f6`), Yosys, OpenROAD, OpenSTA, KLayout.

Design work: **Deepesh J** and **Sai Darshan**. An individual learning project for
OpenLane flow exposure — not a commercial or employer deliverable.
