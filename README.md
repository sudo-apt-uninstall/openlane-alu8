# openlane-alu8

An **8-bit ALU** taken from SystemVerilog RTL through the open-source **OpenLane**
flow on **SCL's 0.8 µm CP8D** open PDK — synthesis → floorplan → PDN → placement →
filler insertion → routing → parasitic extraction → static timing analysis.

**Router DRC clean. Critical path 11.61 ns ⇒ ≈86 MHz (cell delay only — see the caveat).**

> ⚠️ **Status: routed, not signed off.** Gate-level simulation of the routed netlist and
> KLayout DRC/LVS signoff have **not** been run yet. See [Open items](#open-items).
> Nothing here is a tapeout claim.

Companion project: [`openlane-8bit-counter`](https://github.com/sudo-apt-uninstall/openlane-8bit-counter)
— the 8-bit counter that proved this flow end to end (0 DRC, LVS matched, ≈120 MHz).

---

## The design

Purely combinational, no clock, no flip-flops. **29 I/O.**

```
in : a[7:0] + b[7:0] + op[2:0]        = 19
out: result[7:0] + zero + carry       = 10
                                        -- 29
```

| `op` | operation | notes |
|---|---|---|
| `000` | ADD | `temp = {1'b0,a} + {1'b0,b}`, `carry = temp[8]` |
| `001` | SUB | `carry` means **no borrow**: `carry = (a >= b)` |
| `010` | AND | |
| `011` | OR | |
| `100` | XOR | |
| `101` | `a << b[2:0]` | bits above 7 are dropped; `carry` unaffected |
| `110` | `a >> b[2:0]` | bits below 0 are dropped; `carry` unaffected |
| `111` | — | `default`: `result = 0`, `carry = 0` |

`zero` is computed from `result` *after* the `case`, so it is correct for every opcode
including `default`.

Two deliberate RTL choices worth noting, because reviewers often try to "fix" them:

- **Defaults are assigned at the top of `always_comb` before the `case`**, so no latches
  are inferred. This is the single most common ALU bug and it is avoided here.
- **`temp` is 9 bits** and ADD zero-extends both operands, so carry-out is captured
  rather than lost to 8-bit truncation.

---

## Results

| stage | result |
|---|---|
| synthesis (Yosys) | **210 CP8D standard cells** |
| floorplan | 1000 × 1000 µm die, 800 × 800 µm core, **16 rows**, 50.7 µm pitch, ~33 % occupancy |
| PDN | metal1 followpins, 7 µm per row, metal1/metal2 ring |
| placement | `detailed_placement` + `check_placement` clean |
| filler insertion | **566 components = 210 logic + 356 FILLER** |
| routing | **`drc.rpt` 0 bytes — router DRC clean on 2 metal layers** |
| RC extraction | SPEF written, **but capacitance is all zero — PDK limitation, see below** |
| STA | **11.61 ns ⇒ ≈86.1 MHz**, critical path `a[1]` → `zero`, 10 logic levels |

### Cell histogram

```
28 NND200   28 MX2100   23 ORND00   21 NOR200   20 INVR00   18 NND300
15 ADNR00    8 OR2100    8 AOI400    8 AND200    6 NOR300    5 XNR200
 4 XOR200    3 OAI400    3 AND500    3 AND300    2 OR3100    2 NND500
 2 AND400    1 NOR500    1 NND600    1 NND400
```

- **28 × `MX2100`** — the 2:1 mux tree implementing `case (op)`. Expected.
- **No flip-flops**, correctly — the design is combinational.
- **No `ADR100`** (the library's full-adder). Yosys built the carry chain from ordinary
  gates. Reason: ABC is invoked with no delay target and no SDC, so it maps for **area**,
  and the larger full-adder cell loses. Not a library defect.

### 🔴 Mandatory caveat on the 86 MHz number

> **Cell delay only — interconnect parasitics are not modelled by the SCL PDK.**

The SPEF was generated and read, but the OpenRCX rule deck for this process produces
**zero capacitance on every net**. The figure is also **typical corner only** (5 V,
25 °C); CP8D ships no worst-case library. Real post-layout timing will be slower.
This must never be presented as signoff timing.

For scale on how slow this process is: `NND600` alone costs **2.50 ns**.

---

## Running it

The flow is driven from the OpenLane container prompt, one script at a time.
`run_openroad_script` takes a **path** argument and prints nothing on success — check
`runs/RUN/results/`, and check **file sizes**, not just existence.

```tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/pdn_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/placement_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/fill_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/routing_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/rcx_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/run_sta.tcl
```

🔴 **Never run `cts_cp8d.tcl`** — it calls `[get_ports clk]` and this design has no clock
port. `fill_cp8d.tcl` replaces it; see [docs/flow-notes.md](docs/flow-notes.md).

---

## What had to change to run a combinational design

The SCL reference flow was built around a **clocked** counter. Six input-side changes
were needed. Full detail in [docs/flow-notes.md](docs/flow-notes.md).

1. `alu8.sv` copied to `1_RTL/alu8.v` — the Yosys script hardcodes `DESIGN_NAME.v`.
   **The content is still SystemVerilog; only the extension changed.**
2. `-sv` added to `read_verilog` in `yosys_script.tcl`.
3. `config.json` — `CLOCK_PORT ""`, `CLOCK_NET ""`, `RUN_CTS false`, 1000 µm die.
4. `pin_order.cfg` — 29 pins across the four edges.
5. `run_sta.tcl` — a **virtual clock** replacing `create_clock ... [get_ports clk]`.
6. **`fill_cp8d.tcl`** — a new, hand-written CTS substitute that preserves filler
   insertion. The reference flow only inserts fillers *inside* CTS, so skipping CTS
   silently loses them.

**Provenance:** of the 10 reference Tcl scripts, **8 are byte-identical to SCL's
upstream** and only `run_sta.tcl` and `yosys_script.tcl` differ — exactly the two edits
above. Every result here is stock-script output.

---

## Open items

1. **Gate-level simulation of the routed netlist — not run.** The inputs exist
   (`alu8_rt_sim.v`, which carries no supply pins and so drops straight into the
   existing testbench, plus `alu8_rt.sdf`). This is the only step that verifies the
   routed netlist actually *computes correctly*.
2. **KLayout DRC/LVS signoff — not run.** Router DRC ≠ signoff DRC; the 0-byte
   `drc.rpt` above is the router's own check, not the full rule deck.
3. **Wire-load RC experiment** inconclusive — the modified script appears never to have
   reached disk.

### Known RTL gaps

- No signed **overflow** flag (`carry` is the unsigned indicator only).
- Shifts drop ejected bits and never set `carry`; the convention is undecided.
- `op = 3'b111` is never exercised by the testbench, so the `default` branch is dead in
  simulation.
- The testbench is **9 directed vectors**. A full `a × b × op` sweep is only
  8 × 256 × 256 = 524,288 evaluations — trivially runnable, and it would *prove* the
  design rather than sample it.

---

## A note on tap cells

A reasonable instinct on a CMOS flow is "insert tap cells to guarantee well/substrate
contact and prevent latch-up." **On CP8D that does not apply:** the library ships
**no tap/welltap/subtap macro at all** — 65 LEF macros against 59 Liberty cells, and
the six LEF-only ones are exactly `FILLER1`…`FILLER6`. The only other physical-only
cells are `VDDCON` (`TIEHI`) and `VSSCON` (`TIELO`), which are tie cells.

At 0.8 µm the well and substrate contacts are drawn **inside each standard cell and
inside the fillers**; the separate-tap-cell-on-a-pitch scheme is a deep-submicron
convention. **On this process, filler insertion *is* the tap strategy** — which is
precisely why the `fill_cp8d.tcl` rescue above matters.

---

## Repository layout

```
rtl/        alu8.sv, tb_alu8.sv
netlist/    alu8_netlist.v  — generic Yosys output, NOT technology-mapped
docs/       flow notes
```

⚠️ `netlist/alu8_netlist.v` is Yosys **generic** output: 322 `assign` statements, 318
wires, **zero cell instances**. It is kept for provenance only. **No area, cell-count or
timing number may be quoted from it** — OpenLane re-synthesises from `1_RTL/` anyway.

---

## Credits and licensing

PDK: **SCL Mohali** 0.8 µm CP8D open PDK, distributed via echiphub.in / NIELIT.
**The PDK itself is not redistributed in this repository.**

Tooling: OpenLane v1.0.2 (`ff5509f6`), Yosys, OpenROAD, OpenSTA, KLayout.

Design work: Deepesh J and Sai Darshan. Individual learning project for OpenLane flow
exposure — **not** a commercial or employer deliverable.
